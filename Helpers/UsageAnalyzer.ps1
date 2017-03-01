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

function ConvertToCTime ([datetime]$InputEpoch) {
    [datetime]$Epoch = '1970-01-01 00:00:00'
    $Ctime = (New-TimeSpan -Start $Epoch -End $InputEpoch).TotalMilliseconds
    return $Ctime
}

function translate-state {
    param (
        $state
    )
    
    switch ($State) {
        "idle" {return "idle" }
        "standby" {return "standby" }
        "off" {return "off"; break }
        "active" {return "active" }
        "inactive" {return "idle" }
        "logged off" {return "idle" }
        "invalid" {return "invalid" }
        "on" {return "active" }
    }
}

function parse-rawstates {
    param (
        [Parameter(ValueFromPipeline=$true)]
        $RawState
    )
    begin {}

    process {
        foreach ($State in $RawState) {

            $Pattern = [regex]("(\w*), \( \( (\w*, \d* \w* \d* \d*:\d*:\d* -\d*) to (\w*, \d* \w* \d* \d*:\d*:\d* -\d*) \), (.*?) \)")
    
            $State -match ($Pattern) | out-null

            return @{
                "Computer" = $Matches[1]
                "Start" = [datetime]$Matches[2]
                "End" = [datetime]$Matches[3]
                "State" = $Matches[4]
            }
        }
    }
    end {}
}

#$Days = 14
$Minutes = $Days * 60 * 24

#$Resolution = 60

[datetime] $Start = [datetime]::Today.adddays(-1 * $Days)
[datetime] $End = [datetime]::Today
try {
    $RawStates = Invoke-BFSessionQuery -Server $BigFix -Query "unique values of (it as string) of (name of computer of it, values of it) of results from (bes properties whose (name of it contains ""Power - All Power States - Win\Mac"")) of members of bes computer group whose (name of it is ""$ComputerGroup"")" -Credential $Credential -erroraction stop
} catch {
    write-error "Error connecting to BigFix"
    exit
}
#$RawStates = get-content ".\Input.txt"

write-host "Parsing Power States"
$ParsedStates = $RawStates | parse-rawstates

$Results = @()

write-host "Loading Power State Array"

for ($Minute = 0; $Minute -lt $Minutes; $Minute += $Resolution) {
#foreach ($Minute in 0 .. $Minutes) {
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

write-host "Processing Power States"

$Count = $ParsedStates.Count
$Number = 0

#ParsedStates SHOULD be FASTER
foreach ($State in $ParsedStates) {
    
    #Logging
    $Number++
    if ($Number % 500 -eq 0) { write-host "Processing $Number of $Count" }

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

write-host "Merging up Duplicate States"
for ($Index = 0; $index -lt $Results.count; $Index++) {
    $Results[$Index].idle += $Results[$Index].inactive + $results[$Index].'logged off'
    $Results[$Index].active += $Results[$Index].on
    $Results[$Index] = $Results[$Index] | Select-Object -Property * -ExcludeProperty inactive,'logged off',on
}

write-host "Preparing JSON Output"
# Merge for Graphing
$Active = $null
$Idle = $null
$Standby = $null
$Off = $null

foreach ($Result in $Results) {
    $Active += , @((ConvertToCTime($Start.AddMinutes($Result.Time).touniversaltime())), $Result.active)
    $Idle += , @((ConvertToCTime($Start.AddMinutes($Result.Time).touniversaltime())), $Result.Idle)
    $Standby += , @((ConvertToCTime($Start.AddMinutes($Result.Time).touniversaltime())), $Result.Standby)
    $Off += , @((ConvertToCTime($Start.AddMinutes($Result.Time).touniversaltime())), $Result.Off)
}

$JSON = @(
            @{"key" = "Active"; "values" = ($Active)}
            @{"key" = "Idle"; "values" = ($Idle)}
            @{"key" = "Standby"; "values" = ($Standby)}
            @{"key" = "Off"; "values" = ($Off)}
        )

$RawJSON = convertto-json $JSON -depth 10 -compress

$MyChart = get-content .\NewChartInput.html

$MyChart = $MyChart -replace ("!ReplaceMe!",$RawJSON)

$MyChart | Set-content ".\$OutFile"

#$Results | export-csv output1.csv -NoTypeInformation