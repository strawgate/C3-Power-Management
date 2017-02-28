
Add-Type -AssemblyName System.Web

<# Add exception for self-signed certificates
    BigFix uses a custom self-signed private cert for API activities
    So we have to go against our better judgement here and accept self-signed certificates
#>
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

<#  Import the system.security assembly for crypto handling
    This is not imported into the standard powershell environment so we need it to prevent
    the error: "Unable to find type [Security.Cryptography.ProtectedData]."
#>

Add-Type -AssemblyName System.Security
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RESTAPI = @{
    "Sourced Fixlet Action" = [xml] @"
<?xml version="1.0" encoding="UTF-8"?>
<BES>
 <SourcedFixletAction>
   <SourceFixlet>
     <Sitename></Sitename>
     <FixletID></FixletID>
     <Action>Action1</Action>
   </SourceFixlet>
   <Target></Target>
 </SourcedFixletAction>
</BES>
"@
}

function Invoke-BFAction {
    param (
        [string]$Site,
        [string]$Fixlet,
        [string]$Action,
        [string[]]$Target,
        [string]$Server,
        $Credential
    )

    write-verbose "Preparing sourced fixlet action"

    $Template = $RESTAPI.'Sourced Fixlet Action'
    
    write-verbose "Action $Action from Fixlet $Fixlet in $Site"

    $Template.BES.SourcedFixletAction.SourceFixlet.Sitename = $Site
    $Template.BES.SourcedFixletAction.SourceFixlet.FixletID = $Fixlet
    $Template.BES.SourcedFixletAction.SourceFixlet.Action   = $Action
    
    foreach ($ID in $Target) {
        Write-Verbose "Adding $ID to targeting"

        $ComputerID = $Template.CreateElement("ComputerID")
        $ComputerID.InnerText = "$ID"

        $Template.BES.SourcedFixletAction.Target.AppendChild($ComputerID) | out-null
    }
    write-verbose "Posting Action"

    try {
       $Response = Invoke-BFWebRequest -Server $Server -Type "actions" -Method post -Body $Template.InnerXML -Credential $Credential

        write-verbose "Success -- New Action $($Response.BESAPI.Action.ID)"
    
        write-output $Response.BESAPI.Action.ID
    } catch {
        write-error "Failed invoking action: $($Template.InnerXML)"
    }
}


Function Invoke-BFWebRequest {
    param (
        [string]$Server,
        [string]$Type,
        $Method,
        [xml]$Body,
        $Credential
    )

    $uri = [uri](Get-BFRestURI -Server $Server -Path $Type)

    $Response = Invoke-WebRequest -Uri $uri.AbsoluteUri -Method $Method -Credential $Credential -Body $Body

    return Invoke-NullCoalescing (select-xml -content ($Response) -xpath "/" -ErrorAction SilentlyContinue).Node $Response.Content 
}

Function Get-BFRestURI {
    param (
        [string]$Server,
        [string]$Path
    )
    
    write-output "https://$($Server):52311/api/$Path"
}

Function Get-BFComputerID {
    param (
        [string]$Server,
        [parameter(ValueFromPipelineByPropertyName)]
        [Alias('IPAddress','CN')]
        [string[]]$Computername,
        $credential
    )
    begin {}

    process {
        foreach ($Computer in $Computername) {
            try {
                write-verbose "Checking Computer ID of Computer $Computer"

                $Query = "id of bes computers whose (name of it as lowercase is ""$Computer"" as lowercase and last report time of it = maximum of last report times of bes computers whose (name of it as lowercase is ""$Computer"" as lowercase))"

                Invoke-BFSessionQuery -Query $Query -Server $Server -Credential $Credential
                
                write-verbose "Done checking Computer ID of Computer $Computer"
            } catch {
                write-error "Could not find computer with name $Computer"
            }
        }
    }

    end{}
}

#Arbitrary Query
Function Invoke-BFSessionQuery {

    param (
        [string]$Server,
        [string]$Query,
        $Credential
    )

    $EncodedQuery = [System.Web.HttpUtility]::UrlEncode($Query)

    write-verbose "Running Query $EncodedQuery against $Server"

    $Response = Invoke-BFWebRequest -Server $Server -Type "query?relevance=$EncodedQuery" -Method Get -Credential $Credential
    
    write-verbose "Result $($Response.InnerXml)"

    if ($Response.BESAPI.Query.Error){
        throw "Query returned an error: $($Response.BESAPI.Query.Error)"
    }
    
    write-output $Response.BESAPI.Query.Result.Answer.'#Text'
}

function Invoke-NullCoalescing {
   $args | Where-Object { $_ -ne $null } | Select-Object -First 1
}

Export-ModuleMember -function Get-BFComputerID
Export-ModuleMember -function Invoke-BFAction
Export-ModuleMember -Function Invoke-BFSessionQuery