function EnsureFileStartsWithLine($LiteralPath, $Line) {
    if (Test-Path -LiteralPath $LiteralPath) {
        $Lines = @(Get-Content -LiteralPath $LiteralPath)
    } else {
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
