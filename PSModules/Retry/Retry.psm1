Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function CutoffAtSimilarExecutionTime($ExecutionHistory) {
    $Threshold = .15

    if ($ExecutionHistory.Count -lt 2) { return $false }
    
    $LastDuration = $ExecutionHistory[0].EndTime - $ExecutionHistory[0].StartTime
    $NextToLastDuration = $ExecutionHistory[1].EndTime - $ExecutionHistory[1].StartTime
    $DurationRatio = $LastDuration.TotalMilliseconds / $NextToLastDuration.TotalMilliseconds
    
    return `
        ($DurationRatio -lt (1 + $Threshold)) -and `
        ($DurationRatio -gt (1 - $Threshold))
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
    'SimilarExecutionTime' = $function:CutoffAtSimilarExecutionTime
}

function RecordExecution {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidGlobalVars", "global:LASTEXITCODE")]
    Param([ScriptBlock]$ScriptBlock)
    
    $Exception = $null
    $Output = $null
    $ExitCode = $null
    $StartTime = Get-Date
    try {
        $global:LASTEXITCODE = 0
        $Output = & $ScriptBlock
        $ExitCode = $global:LASTEXITCODE

        $Succeeded = ($ExitCode -eq 0)
    } catch {
        $Succeeded = $false
        $Exception = $_ 
    }
    $EndTime = Get-Date

    return New-Object PSObject -Property @{
        'Output' = $Output
        'Succeeded' = $Succeeded
        'ExitCode' = $ExitCode
        'Exception' = $Exception
        'StartTime' = $StartTime
        'EndTime' = $EndTime
        'Duration' = $EndTime - $StartTime
        'DurationMs' = ($EndTime - $StartTime).TotalMilliseconds
    }
}

function RecordExecutionWithRetry(
    $ScriptBlock,
    $CutoffFunction,
    $BackoffFunction
) {
    $ExecutionHistory = @()

    do {
        $ExecutionHistory = @(RecordExecution $ScriptBlock) + $ExecutionHistory
    } while (-not $ExecutionHistory[0].Succeeded -and -not (& $CutoffFunction $ExecutionHistory))

    return $ExecutionHistory
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
                   Position=1)]
        [ValidateSet('None', 'SimilarExecutionTime', 'SameOutput')]
        [string]
        $CutoffStrategy = 'SameOutput'
    )
    $CutoffFunction = $CutoffFunctions[$CutoffStrategy]
    $BackoffFunction = $BackoffFunctions[$BackoffStrategy]

    $ExecutionHistory = RecordExecutionWithRetry -ScriptBlock $ScriptBlock -CutoffFunction $CutoffFunction -BackoffFunction $BackoffFunction

    return $ExecutionHistory[0].Output
}

Export-ModuleMember -Function @(
    'Invoke-WithRetry'
)