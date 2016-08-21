Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
New-PesterOption -IncludeVSCodeMarker

Import-Module -Name $PSScriptRoot\Retry.psm1 -Force

Describe "RecordExecution" {
    InModuleScope Retry {
        It 'should record output accurately' {
            (RecordExecution { 27 }).Output | Should Be 27
        }

        $AcceptableTimingThresholdMs = 50

        It 'should record duration of short command accurately' {
            (RecordExecution { 27 }).DurationMs | Should BeLessThan $AcceptableTimingThresholdMs
        }

        It 'should record duration of long commands accurately' {
            $SleepDurationMs = 200
            $RecordedSleep = RecordExecution { Start-Sleep -Milliseconds $SleepDurationMs }
            
            $RecordedSleep.DurationMs | Should BeLessThan    ($SleepDurationMs + $AcceptableTimingThresholdMs)
            $RecordedSleep.DurationMs | Should BeGreaterThan ($SleepDurationMs - $AcceptableTimingThresholdMs)
        }

        It 'should detect thrown exceptions as non-success' {
            (RecordExecution { throw "error" }).Succeeded | Should Be $false
        }

        It 'should detect Write-Error as non-success' {
            (RecordExecution { Write-Error "error" }).Succeeded | Should Be $false
        }

        It 'should detect normal execution as success' {
            (RecordExecution { 27 }).Succeeded | Should Be $true
        }

        It 'should detect non-zero error codes as non-success' {
            (RecordExecution { cmd /c exit /b 1 }).Succeeded | Should Be $false
        }

        It 'should detect zero error codes as success' {
            (RecordExecution { cmd /c exit /b 0 }).Succeeded | Should Be $true
        }
    }
}

Describe "CutoffAtSameOutput" {
    InModuleScope Retry {
        It 'should not cut off after 1 try' {
            CutoffAtSameOutput @(RecordExecution {27}) | Should Be $false
        }

        It 'should not cut off after 2 different outputs' {
            CutoffAtSameOutput @(
                (RecordExecution {27}),
                (RecordExecution {28})
            ) | Should Be $false
        }

        It 'should cut off after 2 identical outputs' {
            CutoffAtSameOutput @(
                (RecordExecution {27}),
                (RecordExecution {27})
            ) | Should Be $true
        }
    }
}

Describe "CutoffAtSimilarExecutionTime" {
    InModuleScope Retry {
        It 'should not cut off after 1 try' {
            CutoffAtSimilarExecutionTime @(RecordExecution {27}) | Should Be $false
        }

        It 'should cut off after 2 similarly timed short tasks' {
            CutoffAtSimilarExecutionTime @(
                (RecordExecution { }),
                (RecordExecution { })
            ) | Should Be $true
        }

        It 'should cut off after 2 similarly timed long tasks' {
            CutoffAtSimilarExecutionTime @(
                (RecordExecution { Start-Sleep -Milliseconds 200 }),
                (RecordExecution { Start-Sleep -Milliseconds 200 })
            ) | Should Be $true
        }

        It 'should not cut off after 2 differently timed tasks' {
            CutoffAtSimilarExecutionTime @(
                (RecordExecution { Start-Sleep -Milliseconds 200 }),
                (RecordExecution { })
            ) | Should Be $false
        }
    }
}

Describe "RecordExecutionWithRetry" {
    InModuleScope Retry {
        It 'should only execute a successful ScriptBlock once' {
            $History = @(RecordExecutionWithRetry -ScriptBlock { } -CutoffFunction { $false } -BackoffFunction { })

            $History.Count | Should Be 1
        }

        It 'should cut off at the first success regardless of cutoff policy' {
            $script:calls = 0
            $History = RecordExecutionWithRetry -ScriptBlock {
                $script:calls += 1
                if ($script:calls -lt 3) { throw "error" }
            } -CutoffFunction { $false } -BackoffFunction { }

            $History.Count | Should Be 3
        }

        It 'should cut off according to the cut off function' {
            $script:calls = 0
            $History = RecordExecutionWithRetry -ScriptBlock {
                $script:calls += 1
                throw "error"
            } -CutoffFunction {
                return $script:calls -ge 4
            } -BackoffFunction { }

            $History.Count | Should Be 4
        }
    }
}

Describe 'Invoke-WithRetry' {
    It 'Should return the output from the last execution history item' {
        Mock -ModuleName Retry RecordExecutionWithRetry {
            return @(
                (New-Object PSObject -Property @{Output = 2}),
                (New-Object PSObject -Property @{Output = 1}))
        }

        Invoke-WithRetry -ScriptBlock { } | Should Be 2
    }
}