Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$EnvDirectory = $PSScriptRoot # Typically C:\Code\dbjorge-env
$CodeDirectory = Split-Path $PSScriptRoot #Typically C:\Code
$EnvPSModuleDirectory = Join-Path $EnvDirectory 'PSModules'
Import-Module -Force "$EnvPSModuleDirectory\Paths\Paths.psm1"

Register-PathElement -PathElement @(
    (Join-Path $CodeDirectory 'depot_tools')
)

Register-PathElement -PathEnvironmentVariable 'PSModulePath' -PathElement @(
    $EnvPSModuleDirectory
)

$env:DEPOT_TOOLS_WIN_TOOLCHAIN = 0

New-Alias -Force -Name 'subl' -Value 'C:\Program Files\Sublime Text 3\subl.exe'
New-Alias -Force -Name 'code' -Value 'C:\Program Files (x86)\Microsoft VS Code\Code.exe'
New-Alias -Force -Name 'which' -Value 'Get-Command'
