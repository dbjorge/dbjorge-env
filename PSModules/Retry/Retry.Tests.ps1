Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
New-PesterOption -IncludeVSCodeMarker

Import-Module -Name $PSScriptRoot\Retry.psm1 -Force

InModuleScope Retry {
    function FailedExecutionRecord($Output, $DurationMs=10) {
        $StartTime = Get-Date
        $EndTime = $StartTime.AddMilliseconds($DurationMs)
        CreateExecutionRecord $Output 1 $null $StartTime $EndTime
    }

    Describe "CutoffAtSameOutput" {
        It 'should not cut off after 1 try' {
            CutoffAtSameOutput @(FailedExecutionRecord -Output 27) | Should Be $false
        }

        It 'should not cut off after 2 different outputs' {
            CutoffAtSameOutput @(
                (FailedExecutionRecord -Output 27),
                (FailedExecutionRecord -Output 28)
            ) | Should Be $false
        }

        It 'should cut off after 2 identical outputs' {
            CutoffAtSameOutput @(
                (FailedExecutionRecord -Output 27),
                (FailedExecutionRecord -Output 27)
            ) | Should Be $true
        }
    }

    Describe "CutoffAtSimilarExecutionTime" {
        It 'should not cut off after 1 try' {
            CutoffAtSimilarExecutionTime @(FailedExecutionRecord -Output 27) | Should Be $false
        }

        It 'should cut off after 2 similarly timed short tasks' {
            CutoffAtSimilarExecutionTime @(
                (FailedExecutionRecord -Output 27 -DurationMs 0),
                (FailedExecutionRecord -Output 27 -DurationMs 49)
            ) | Should Be $true
        }

        It 'should not cut off after 2 differently timed short tasks' {
            CutoffAtSimilarExecutionTime @(
                (FailedExecutionRecord -Output 27 -DurationMs 0),
                (FailedExecutionRecord -Output 27 -DurationMs 51)
            ) | Should Be $false
        }

        It 'should cut off after 2 similarly timed long tasks' {
            CutoffAtSimilarExecutionTime @(
                (FailedExecutionRecord -Output 27 -DurationMs 120000),
                (FailedExecutionRecord -Output 27 -DurationMs 130000)
            ) | Should Be $true
        }

        It 'should not cut off after 2 differently timed long tasks' {
            CutoffAtSimilarExecutionTime @(
                (FailedExecutionRecord -Output 27 -DurationMs 150000),
                (FailedExecutionRecord -Output 27 -DurationMs 120000)
            ) | Should Be $false
        }
    }

    Describe "RecordExecution" {
        It 'should output what the scriptblock outputs' {
            $Record = $null
            RecordExecution { 27 } ([ref]$Record) | Should Be 27
        }

        It 'should record output accurately' {
            $Record = $null
            RecordExecution { 27 } ([ref]$Record)
            $Record.Output | Should Be 27
        }

        $AcceptableTimingThresholdMs = 50

        It 'should record duration of short commands accurately' {
            $Record = $null
            RecordExecution { 27 } ([ref]$Record)
            $Record.DurationMs | Should BeLessThan $AcceptableTimingThresholdMs
        }

        It 'should record duration of long commands accurately' {
            $SleepDurationMs = 200
            $Record = $null
            RecordExecution { Start-Sleep -Milliseconds $SleepDurationMs } ([ref]$Record)
            
            $Record.DurationMs | Should BeLessThan    ($SleepDurationMs + $AcceptableTimingThresholdMs)
            $Record.DurationMs | Should BeGreaterThan ($SleepDurationMs - $AcceptableTimingThresholdMs)
        }

        It 'should detect thrown exceptions as non-success' {
            $Record = $null
            RecordExecution { throw "error" } ([ref]$Record)
            $Record.Succeeded | Should Be $false
        }

        It 'should detect Write-Error as non-success' {
            $Record = $null
            RecordExecution { Write-Error "error" } ([ref]$Record)
            $Record.Succeeded | Should Be $false
        }

        It 'should detect normal execution as success' {
            $Record = $null
            RecordExecution { 27 } ([ref]$Record)
            $Record.Succeeded | Should Be $true
        }

        It 'should detect non-zero error codes as non-success' {
            $Record = $null
            RecordExecution { cmd /c exit /b 1 } ([ref]$Record)
            $Record.Succeeded | Should Be $false
        }

        It 'should detect zero error codes as success' {
            $Record = $null
            RecordExecution { cmd /c exit /b 0 } ([ref]$Record)
            $Record.Succeeded | Should Be $true
        }
    }

    Describe "RecordExecutionWithRetry" {
        It 'should only execute a successful ScriptBlock once' {
            $History = $null
            RecordExecutionWithRetry `
                -ScriptBlock { } `
                -CutoffFunction { $false } `
                -BackoffFunction { } `
                -ExecutionHistory ([ref]$History)

            $History.Count | Should Be 1
        }

        It 'should cut off according to the cut off function' {
            $script:calls = 0
            $History = $null
            RecordExecutionWithRetry `
                -ScriptBlock { $script:calls += 1; throw "error" } `
                -CutoffFunction { $script:calls -ge 4 } `
                -BackoffFunction { } `
                -ExecutionHistory ([ref]$History)

            $History.Count | Should Be 4
        }
    }
}


$script:calls = 0
function TrackCallsAndThrowUntil($CallsUntilSuccess) {
    $script:calls += 1
    if ($script:calls -lt $CallsUntilSuccess) {
        throw "TrackCallsAndThrowUntil error at call " + $script:calls
    }
    Write-Debug ("TrackCallsAndThrowUntil succeeding at call " + $script:calls)
    $script:calls = 0
}

Describe 'Invoke-WithRetry' {
    It 'should cut off at the first success regardless even with no cutoff policy' {
        $script:CallCount = 0
        Invoke-WithRetry { $script:CallCount += 1; TrackCallsAndThrowUntil 3 } -CutoffStrategy 'None'
        $script:CallCount | Should Be 3
    }

    It 'Should return the output from the last execution history item in Output Last mode' {
        Invoke-WithRetry { "line"; TrackCallsAndThrowUntil 3 } -CutoffStrategy 'None' -Output 'Last' | Should Be "line"
    }

    It 'Should output as it occurs in Output All mode' {
        Invoke-WithRetry { "line"; TrackCallsAndThrowUntil 3 } -CutoffStrategy 'None' -Output 'All' | Should Be "line","line","line"
    }
}