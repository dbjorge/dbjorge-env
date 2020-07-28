# Partially taken from razzle.ps1 in the OS repo
#
# Provides Write-Prompt, which:
#   => If the last command took > 3 seconds, it tells you precisely how long the last command took
#   => If the last command took > 20 seconds, it beeps (because you'll inevitably <Alt-Tab>)
#   => Shows cwd
#   => Shows the posh-git info (and does it in a fast/gvfs-compatible way)
#   => Shows the index in Get-History
#   => Shows the time & date
#   => Understands how to break long prompt text across multiple lines

$LocationColor = "$([char]27)[97m"
$PoshGitBracketColor = "$([char]27)[93m"
$BranchColor = "$([char]27)[96m"
$HistoryIdColor = "$([char]27)[93m"
$TimeStampColor = "$([char]27)[32m"
$LastCommandDurationColor = "$([char]27)[93m"

$ResetColor = "$([char]27)[m"

# This is more performant than the usual git rev-parse technique in GVFS branches
$script:CachedGitOriginUrlsByFolder = @{}
function Get-GitBranchInfo
{
    $folder = Get-GitFolder
    if ($null -eq $folder) { return $null; }

    if (-not $script:CachedGitOriginUrlsByFolder.ContainsKey($folder)) {
        $script:CachedGitOriginUrlsByFolder[$folder] = git config --local remote.origin.url
    }
    $originUrl = $script:CachedGitOriginUrlsByFolder[$folder]

    if (Test-Path "$folder\HEAD") {
        $branch = ((Get-Content -Force "$folder\HEAD") -replace '^ref: refs\/heads\/','');
    } else {
        # probably a submodule case
        $branch = git rev-parse --abbrev-ref HEAD
    }

    return New-Object PSObject -Property @{
        Folder = $folder;
        Branch = $branch;
        OriginUrl = $originUrl;
        IsLargeGvfsRepo = ($originUrl -match '/_git/os$');
    }
}

function Get-GitFolder
{
    # Scan up from pwd for .git folders and identify HEAD from that
    $old = ""
    $current = $pwd.Path
    while ($current -ne $old)
    {
        if (Test-Path "$current\.git")
        {
            return "$current\.git"
        }

        $old = $current
        $current = (Resolve-Path "$current\..").Path
    }
}

function Write-GvfsCapableGitStatus($BranchInfo) {
    if ($branchInfo) {
        if ($branchInfo.IsLargeGvfsRepo) {
            # Formatting chosen for posh-git compatibility
            Write-Host " $($PoshGitBracketColor)[$($BranchColor)$($branchInfo.Branch)$($PoshGitBracketColor)]$($ResetColor)" -NoNewline
        } else {
            # This is too slow in the big repos (even using RepositoriesInWhichToDisableFileStatus), but nicer elsewhere
            Write-VcsStatus
        }
    }
}

$script:LastHistoryItemProcessed = 0
function Write-PromptEx {
    $historyItem = Get-History -Count 1
    $id = 1

    if ($historyItem -and ($script:LastHistoryItemProcessed -lt $historyItem.Id))
    {
        ## Check if the last command took a long time
        $lastCommandElapsedTime = $historyItem.EndExecutionTime - $historyItem.StartExecutionTime

        if ($lastCommandElapsedTime.TotalSeconds -gt 3 -or $LASTEXITCODE -ne 0)
        {
            $lastCommandDurationString = `
                if ($lastCommandElapsedTime.TotalHours -gt 1) {
                    ("{0:#0}:{1:00}:{2:00}.{3:000}" -f (($lastCommandElapsedTime.Days * 24) + $lastCommandElapsedTime.Hours), $lastCommandElapsedTime.Minutes, $lastCommandElapsedTime.Seconds, $lastCommandElapsedTime.Milliseconds)
                } elseif ($lastCommandElapsedTime.TotalMinutes -gt 1) {
                    ("{0:#0}:{1:00}.{2:000}" -f $lastCommandElapsedTime.Minutes, $lastCommandElapsedTime.Seconds, $lastCommandElapsedTime.Milliseconds)
                } else {
                    ("{0} seconds" -f $lastCommandElapsedTime.TotalSeconds)
                }

            Write-Host "$($LastCommandDurationColor)Exit code $LASTEXITCODE. Command took $lastCommandDurationString.$($ResetColor)"
        }

        # if it took longer than 20 seconds, beep to let the user know it's done
        if ($lastCommandElapsedTime.TotalSeconds -gt 20) {
            [Console]::Beep(500,200)
        }

        $script:LastHistoryItemProcessed = $historyItem.Id
    }

    if ($historyItem)
    {
        $id = $historyItem.Id + 1
    }

    $TimeStamp = "{0:HH:mm:ss} {0:MM/dd}" -f ([DateTime]::Now)

    $location = (Get-Location).Path
    $location = [Regex]::Replace($location, '^' + [Regex]::Escape($global:HOME), '~')

    $branchInfo = Get-GitBranchInfo
    $windowWidth = $host.UI.RawUI.WindowSize.Width
    $bufferCharsToAllowFor = ' [ ≡12 +12 ~12 -12 !] | 123 | 12:34:56 78/90'.Length
    $use2Lines = (($location.Length + $branchInfo.Branch.Length + $bufferCharsToAllowFor) -gt $windowWidth)

    Write-Host ""
    Write-Host "$($LocationColor)$($location)$($ResetColor)" -NoNewline
    if ($use2Lines) { Write-Host "`n   " -NoNewline }
    Write-GvfsCapableGitStatus $branchInfo
    Write-Host " | $($HistoryIdColor)$($id)$($ResetColor) | $($TimeStampColor)$($TimeStamp)$($ResetColor)"
    Write-Host ">" -NoNewline

    $windowTitle = $location
    if ($env:_BuildWTitle) {
        $windowTitle = $env:_BuildWTitle + ' ' + $windowTitle
    }
    $host.UI.RawUI.WindowTitle = $windowTitle

    " " # Must be returned to prevent default behavior showing through
}

Export-ModuleMember -Function @('Write-PromptEx')