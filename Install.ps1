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