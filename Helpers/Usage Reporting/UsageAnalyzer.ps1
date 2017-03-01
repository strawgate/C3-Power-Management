param (
    $Resolution = 5,
    $Days = 7,
    [Parameter(Mandatory=$true)]
    $BigFix,
    [Parameter(Mandatory=$true)]
    $ComputerGroup,
    $Credential = (get-credential),
    $OutFile = "MyReport.html"
)

import-module .\BFRESTAPI.PSM1 -force

<#
.Synopsis
   Convert a datetime object to Unix Epoch 
.DESCRIPTION
   Takes a .Net Datetime object and converts it to unix epoch time.
.EXAMPLE
   ConvertTo-Epoch [datetime]::now
.EXAMPLE
   ConvertTo-Epoch [datetime]::today
#>
function ConvertTo-Epoch {
    param (
        [datetime]$InputEpoch
    )

    write-output ((New-TimeSpan -Start ([datetime]'1970-01-01 00:00:00') `
                         -End ($InputEpoch).ToUniversalTime() `
           ).TotalMilliseconds)
}

<#
#   Prepare Required Time Variables
#>

$Minutes = $Days * 60 * 24
[datetime] $Start = [datetime]::Today.adddays(-1 * $Days)
[datetime] $End = [datetime]::Today

<#
#   Query BigFix for Power Data
#>

write-host "Querying Power Data from BigFix"
try {
    $RawStates = Invoke-BFSessionQuery -Server $BigFix `
                                        -Query "(item 0 of it, preceding text of first "" to "" of tuple string items 0 of item 1 of it, following text of first "" to "" of tuple string items 0 of item 1 of it, tuple string items 1 of item 1 of it) of (name of computer of it, values of it) of results from (bes properties whose (name of it contains ""Power - All Power States - Win\Mac"")) of members of bes computer group whose (name of it is ""$ComputerGroup"")" `
                                        -Credential $Credential -erroraction stop
} catch {
    write-error "Error connecting to BigFix"
    exit
}

<#
#   Split up Tuple Data
#>

write-host "Parsing Power Data"
$ParsedStates = $RawStates | % {write-output @{
                "Computer" = $_[0]
                "Start" = [datetime]$_[1]
                "End" = [datetime]$_[2]
                "State" = $_[3]
            }}

$Results = @()


<#
#   Prepopulate array with entries
#>

write-host "Preparing Power Data Table"

for ($Minute = 0; $Minute -lt $Minutes; $Minute += $Resolution) {
    $Results += new-object psobject -property @{
        "time" = $Minute
        "active" = 0
        "idle" = 0
        "standby" = 0
        "off" = 0
        "invalid" = 0
        "inactive" = 0
        "logged off" = 0
        "on" = 0
    }
}

write-host "Processing Power Data"

<#
#   Process Power Data into Time Slices based on $Resolution
#>

$Number = 0

foreach ($State in $ParsedStates) {
    
    #Logging
    $Number++
    if ($Number % 500 -eq 0) { write-host "Processing $Number of $($ParsedStates.Count)" }

    #Range Limiting
    if ($State.end -lt $Start -or $State.start -gt $end) { continue }

    if ($State.end -gt $End) { $State.End = $End }
    if ($State.start -lt $Start) { $State.Start = $Start }

    $StartingMinutes = ($State.Start - $Start).TotalMinutes

    $EndingMinutes = ($State.End - $Start).TotalMinutes

    for ($Minute = ($StartingMinutes + ($Resolution - ($StartingMinutes % $Resolution))); $Minute -lt $EndingMinutes; $Minute += $Resolution) {
        if ($Minute -gt $Minutes) {
            write-host "What"
        }

        $Results[$Minute / $Resolution]."$($State.state)" += 1
    }

}

<#
#   Merge Power Data States
#  Specifically, merge Inactive + Logged Off -> Idle
#  Also Merge On -> Active
#>

write-host "Merging duplicate States"
for ($Index = 0; $index -lt $Results.count; $Index++) {
    $Results[$Index].idle += $Results[$Index].inactive + $results[$Index].'logged off'
    $Results[$Index].active += $Results[$Index].on
    $Results[$Index] = $Results[$Index] | Select-Object -Property * -ExcludeProperty inactive,'logged off',on
}

<#
#   Prepare Data into JSON Format Required for Graphing
#>

write-host "Preparing JSON Output"
# Merge for Graphing
$Active = $null
$Idle = $null
$Standby = $null
$Off = $null

foreach ($Result in $Results) {
    $TimeStamp = ConvertTo-Epoch $Start.AddMinutes($Result.Time)

    $Active += , @($TimeStamp, $Result.active)
    $Idle += , @($TimeStamp, $Result.Idle)
    $Standby += , @($TimeStamp, $Result.Standby)
    $Off += , @($TimeStamp, $Result.Off)
}

$JSON = @(
            @{"key" = "Active"; "values" = ($Active)}
            @{"key" = "Idle"; "values" = ($Idle)}
            @{"key" = "Standby"; "values" = ($Standby)}
            @{"key" = "Off"; "values" = ($Off)}
        )

<#
#   Prepare Output
#>
$RawJSON = convertto-json $JSON -depth 10 -compress

<#
#   Use NewChartInput.html as graph template
#>

$MyChart = get-content .\NewChartInput.html

$MyChart = $MyChart -replace ("!ReplaceMe!",$RawJSON)

write-host "Saving to $Outfile"

$MyChart | Set-content ".\$OutFile"

Invoke-Item ".\$OutFile"
