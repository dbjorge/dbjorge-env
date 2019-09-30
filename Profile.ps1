Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module posh-git

$EnvDirectory = $PSScriptRoot
$EnvPSModuleDirectory = Join-Path $EnvDirectory 'PSModules'
Import-Module -Force "$EnvPSModuleDirectory\Paths\Paths.psm1"

Register-PathElement -PathEnvironmentVariable 'PSModulePath' -PathElement @(
    $EnvPSModuleDirectory
)

foreach ($ModuleDirectory in (Get-ChildItem $EnvPSModuleDirectory)) {
    Import-Module -Force -Name $ModuleDirectory.Name
}

New-Alias -Force -Name 'which' -Value 'Get-Command'
