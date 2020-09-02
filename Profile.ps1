Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$MinimumVersion = [System.Management.Automation.SemanticVersion]::Parse('6.2.3')
if ($PSVersionTable.PSVersion -lt $MinimumVersion) {
    Write-Warning "PowerShell version $($PSVersionTable.PSVersion) < minimum required version $MinimumVersion, update at https://github.com/PowerShell/PowerShell/releases"
}

Import-Module posh-git

$EnvDirectory = $PSScriptRoot
$ReposDirectory = Split-Path $EnvDirectory
$EnvPSModuleDirectory = Join-Path $EnvDirectory 'PSModules'
Import-Module -Force (Join-Path $EnvPSModuleDirectory 'Paths' 'Paths.psm1')

Register-PathElement -PathEnvironmentVariable 'PSModulePath' -PathElement @(
    $EnvPSModuleDirectory
)

foreach ($ModuleDirectory in (Get-ChildItem $EnvPSModuleDirectory)) {
    Import-Module -Force -Name $ModuleDirectory.Name
}

while (Test-Path alias:prompt) { Remove-Item alias:prompt }
function global:prompt { Write-PromptEx }

New-Alias -Force -Name 'g' -Value 'git'
New-Alias -Force -Name 'y' -Value 'yarn'

if ($global:IsWindows) {
    while (Test-Path alias:cd) { Remove-Item alias:cd }
    Set-Alias -Force -Name cd -Value Set-LocationEx

    New-Alias -Force -Name 'which' -Value 'Get-Command'

    New-Alias -Force vs2017 'C:\Program Files (x86)\Microsoft Visual Studio\2017\Enterprise\Common7\IDE\devenv.exe'
    New-Alias -Force vs2019 'C:\Program Files (x86)\Microsoft Visual Studio\2019\Enterprise\Common7\IDE\devenv.exe'
    New-Alias -Force vs 'C:\Program Files (x86)\Microsoft Visual Studio\2019\Enterprise\Common7\IDE\devenv.exe'
}

if ($global:IsLinux) {
    if (Test-Path '~/.cargo/bin') {
        Register-PathElement -PathEnvironmentVariable 'PATH' '~/.cargo/bin'
    }

    if (Test-Path '~/.nvm/nvm.sh') {
        function global:nvm { bash -c "source ~/.nvm/nvm.sh && nvm $args" }

        $nodeCurrent = nvm which current
        $nodeDirCurrent = Split-Path $nodeCurrent
        Register-PathElement -PathEnvironmentVariable 'PATH' $nodeDirCurrent
    }
}

if (Test-Command 'exa') {
    New-Alias -Force -Name 'ls' -Value 'exa'
}

function global:cdr { cd $ReposDirectory }
function global:cdas { cd (Join-Path $ReposDirectory 'accessibility-insights-for-android-service')}
function global:cdasc { cd (Join-Path $ReposDirectory 'axe-sarif-converter') }
function global:cdaxe { cd (Join-Path $ReposDirectory 'axe-core') }
function global:cdenv { cd (Join-Path $ReposDirectory 'dbjorge-env') }
function global:cdjorbs { cd (Join-Path $ReposDirectory 'jorbs-spire-mod') }
function global:cdweb { cd (Join-Path $ReposDirectory 'accessibility-insights-web') }
function global:cdwin { cd (Join-Path $ReposDirectory 'accessibility-insights-windows') }

cdr