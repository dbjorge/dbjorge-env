Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-Command([string]$Command) {
    $command = Get-Command $Command -ErrorAction SilentlyContinue;
    return ($command -ne $null);
}

Export-ModuleMember -Function @(
    'Test-Command'
)