$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

<#
.SYNOPSIS
Extended version of Measure-Command. Runs several iterations and presents average+error
#>
function Measure-CommandTimings {
    Param(
        [scriptblock]$Expression,
        [int]$Iterations = 10,
        [int]$WarmupIterations = 3
    )

    1..$WarmupIterations | % { Measure-Command -Expression $Expression } | Out-Null
    $Measurements = 1..$Iterations | % { Measure-Command -Expression $Expression }

    $AggregateMilliseconds = $Measurements | % { $_.TotalMilliseconds } | Measure-Object -Average -Maximum -Minimum
    $AggregateSeconds = $Measurements | % { $_.TotalSeconds } | Measure-Object -Average -Maximum -Minimum
    if ($AggregateSeconds.Average -gt 10) {
        $AggregateMeasurements = $AggregateSeconds
        $UnitString = "s"
    } else {
        $AggregateMeasurements = $AggregateMilliseconds
        $UnitString = "ms"
    }

    $Average = $AggregateMeasurements.Average
    $ErrorMargin = [Math]::Max(
        ($AggregateMeasurements.Maximum - $Average),
        ($Average - $AggregateMeasurements.Minimum))

    return "{0:N0}±{1:N0}$UnitString" -f $Average,$ErrorMargin
}

Set-Alias -Name time -Value Measure-CommandTimings

Export-ModuleMember `
    -Function @(
        'Measure-CommandTimings') `
    -Alias @(
        'time')