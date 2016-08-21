Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function CutoffAtSimilarExecutionTime($ExecutionHistory) {
    $MultiplicativeThreshold = .1
    $AdditiveThresholdMs = 50

    if ($ExecutionHistory.Count -lt 2) { return $false }
    
    $RecentMs = $ExecutionHistory[0].DurationMs
    $PreviousMs = $ExecutionHistory[1].DurationMs

    $DurationRatio = ($RecentMs + 1) / ($PreviousMs + 1)
    
    return `
        ([Math]::Abs($RecentMs - $PreviousMs) -lt $AdditiveThresholdMs) -or
        (($DurationRatio -lt (1 + $MultiplicativeThreshold)) -and `
         ($DurationRatio -gt (1 - $MultiplicativeThreshold)))
}

function CutoffAtSameOutput($ExecutionHistory) {
    if ($ExecutionHistory.Count -lt 2) { return $false }
    
    return $ExecutionHistory[0].Output -eq $ExecutionHistory[1].Output
}

$BackoffFunctions = @{
    'None' = { }
}

$CutoffFunctions = @{
    'None' = { $false }
    'SameOutput' = $function:CutoffAtSameOutput
    'SimilarExecutionTime' = $function:CutoffAtSimilarExecutionTime
}

function CreateExecutionRecord {
    Param(
        $Output,
        $ExitCode,
        $Exception,
        $StartTime,
        $EndTime
    )

    New-Object PSObject -Property @{
        'Output' = $Output
        'Succeeded' = ($null -eq $Exception) -and (0 -eq $ExitCode)
        'ExitCode' = $ExitCode
        'Exception' = $Exception
        'StartTime' = $StartTime
        'EndTime' = $EndTime
        'Duration' = $EndTime - $StartTime
        'DurationMs' = ($EndTime - $StartTime).TotalMilliseconds
    }
}

function RecordExecution {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidGlobalVars", "global:LASTEXITCODE")]
    Param(
        [ScriptBlock]$ScriptBlock,
        [ref]$ExecutionRecord
    )

    $Exception = $null
    $Output = $null
    $ExitCode = $null
    $StartTime = Get-Date
    try {
        $global:LASTEXITCODE = 0
        & $ScriptBlock | Tee-Object -Variable 'Output'
        $ExitCode = $global:LASTEXITCODE
    } catch {
        $Exception = $_ 
    }
    $EndTime = Get-Date

    $ExecutionRecord.Value = CreateExecutionRecord $Output $ExitCode $Exception $StartTime $EndTime
}

function RecordExecutionWithRetry {
    Param (
        [ScriptBlock]$ScriptBlock,
        $CutoffFunction,
        $BackoffFunction,
        [ref]$ExecutionHistory
    )
    $ExecutionHistory.Value = @()

    do {
        $ExecutionRecord = $null
        RecordExecution $ScriptBlock ([ref]$ExecutionRecord)
        $ExecutionHistory.Value = ,($ExecutionRecord) + $ExecutionHistory.Value
    } while (-not $ExecutionHistory.Value[0].Succeeded -and -not (& $CutoffFunction $ExecutionHistory.Value))
}

function Invoke-WithRetry {
    [CmdletBinding()]
    # Forwards whatever the final invocation of $ScriptBlock outputs
    [OutputType($null)]
    param(
        [Parameter(Mandatory=$true,
                   Position=0)]
        [ScriptBlock]
        $ScriptBlock,

        [Parameter(Mandatory=$false,
                   Position=1)]
        [ValidateSet('None')]
        [string]
        $BackoffStrategy = 'None',

        [Parameter(Mandatory=$false,
                   Position=2)]
        [ValidateSet('None', 'SimilarExecutionTime', 'SameOutput')]
        [string]
        $CutoffStrategy = 'SameOutput',

        [Parameter(Mandatory=$false,
                   Position=3)]
        [ValidateSet('All', 'Last')]
        [string]
        $Output = 'All'
    )
    $CutoffFunction = $CutoffFunctions[$CutoffStrategy]
    $BackoffFunction = $BackoffFunctions[$BackoffStrategy]
    $TeeOutput = ($Output -eq 'All')

    $ExecutionHistory = $null
    if ($TeeOutput) {
        RecordExecutionWithRetry -ScriptBlock $ScriptBlock -CutoffFunction $CutoffFunction -BackoffFunction $BackoffFunction -ExecutionHistory ([ref]$ExecutionHistory)
    } else {
        RecordExecutionWithRetry -ScriptBlock $ScriptBlock -CutoffFunction $CutoffFunction -BackoffFunction $BackoffFunction -ExecutionHistory ([ref]$ExecutionHistory) | Out-Null
    }
    
    if ($Output -eq 'Last') {
        $ExecutionHistory[0].Output
    }
}

Export-ModuleMember -Function @(
    'Invoke-WithRetry'
)