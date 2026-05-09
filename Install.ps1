Param(
    [ValidateSet('work', 'personal')]
    [string] $GitProfile
)

function EnsureFileStartsWithLine($LiteralPath, $Line) {
    if (Test-Path -LiteralPath $LiteralPath) {
        $Lines = @(Get-Content -LiteralPath $LiteralPath)
    } else {
        New-Item -Type Directory -Path (Split-Path $LiteralPath) -ErrorAction SilentlyContinue
        $Lines = @()
    }

    if ($Lines.Count -eq 0 -or $Lines[0] -ne $Line) {
        $Lines = @($Line) + $Lines
        $Lines | Out-File -LiteralPath $LiteralPath -Force
    }
}

$ProfileImpl = Join-Path $PSScriptRoot 'Profile.ps1';
EnsureFileStartsWithLine $global:profile ". $ProfileImpl"

$GitConfigImpl = (Join-Path $PSScriptRoot 'gitconfig_global.txt') -replace '\\','/';
EnsureFileStartsWithLine '~/.gitconfig' "[include] path = $GitConfigImpl";

if ($null -ne $env:WSL_INTEROP) {
    $GitConfigWslImpl = (Join-Path $PSScriptRoot 'gitconfig_global_wsl.txt') -replace '\\','/';
    EnsureFileStartsWithLine '~/.gitconfig' "[include] path = $GitConfigWslImpl";
}

$GitConfigProfileInfo = (Join-Path $PSScriptRoot "gitconfig_global_$($GitProfile).txt") -replace '\\','/';
EnsureFileStartsWithLine '~/.gitconfig' "[include] path = $($GitConfigProfileInfo)";

# Configure Claude Code skills symlink
$SkillsDir = Join-Path $PSScriptRoot 'skills';
$ClaudeDir = Join-Path $HOME '.claude';
$ClaudeSkillsLink = Join-Path $ClaudeDir 'skills';
if (-not (Test-Path $ClaudeDir)) {
    New-Item -Type Directory -Path $ClaudeDir | Out-Null;
}
if (Test-Path $ClaudeSkillsLink) {
    $item = Get-Item $ClaudeSkillsLink;
    if ($item.LinkType -eq 'SymbolicLink') {
        Remove-Item $ClaudeSkillsLink;
    } else {
        Write-Warning "$ClaudeSkillsLink exists and is not a symlink, skipping";
    }
}
if (-not (Test-Path $ClaudeSkillsLink)) {
    New-Item -ItemType SymbolicLink -Path $ClaudeSkillsLink -Target $SkillsDir | Out-Null;
}