Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$MinimumVersion = [System.Management.Automation.SemanticVersion]::Parse('6.2.3')
if ($PSVersionTable.PSVersion -lt $MinimumVersion) {
    Write-Warning "PowerShell version $($PSVersionTable.PSVersion) < minimum required version $MinimumVersion, update at https://github.com/PowerShell/PowerShell/releases"
}

Import-Module PSReadLine # PS sometimes disables this if it thinks we're using a screen reader
Import-Module posh-git
$env:POSH_GIT_ENABLED = $true # required for oh-my-posh integration
$GitPromptSettings.BeforeStatus = ''
$GitPromptSettings.AfterStatus = ''

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
if ($global:IsLinux -and (Get-Command oh-my-posh-wsl -ErrorAction SilentlyContinue)) {
    oh-my-posh-wsl --init --shell pwsh --config $PSScriptRoot/dbjorge.omp.json | Invoke-Expression
} elseif (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh --init --shell pwsh --config $PSScriptRoot/dbjorge.omp.json | Invoke-Expression
} else {
    function global:prompt { Write-PromptEx }
}


New-Alias -Force -Name 'g' -Value 'git'
New-Alias -Force -Name 'y' -Value 'yarn'

if ($global:IsWindows) {
    while (Test-Path alias:cd) { Remove-Item alias:cd }
    Set-Alias -Force -Name cd -Value Set-LocationEx

    New-Alias -Force -Name 'which' -Value 'Get-Command'

    New-Alias -Force vs2017 'C:\Program Files (x86)\Microsoft Visual Studio\2017\Enterprise\Common7\IDE\devenv.exe'
    New-Alias -Force vs2019 'C:\Program Files (x86)\Microsoft Visual Studio\2019\Enterprise\Common7\IDE\devenv.exe'
    New-Alias -Force vs 'C:\Program Files (x86)\Microsoft Visual Studio\2019\Enterprise\Common7\IDE\devenv.exe'

    $env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
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

if ($null -ne $env:ANDROID_HOME) {
    $PlatformToolsDirectory = Join-Path $env:ANDROID_HOME 'platform-tools'
    Register-PathElement -PathEnvironmentVariable 'PATH' $PlatformToolsDirectory
}

function global:cdr { cd $ReposDirectory }
function global:cdacn { cd (Join-Path $ReposDirectory 'axe-core-nuget') }
function global:cda { cd (Join-Path $ReposDirectory 'accessibility-insights-action') }
function global:cdas { cd (Join-Path $ReposDirectory 'accessibility-insights-for-android-service') }
function global:cdasp { cd (Join-Path $ReposDirectory 'accessibility-insights-for-android-service-private') }
function global:cdasc { cd (Join-Path $ReposDirectory 'axe-sarif-converter') }
function global:cdaxe { cd (Join-Path $ReposDirectory 'axe-core') }
function global:cddocs { cd (Join-Path $ReposDirectory 'accessibility-insights-docs') }
function global:cdengms { cd (Join-Path $ReposDirectory '1ES-on-EngHub') }
function global:cdenv { cd (Join-Path $ReposDirectory 'dbjorge-env') }
function global:cdjorbs { cd (Join-Path $ReposDirectory 'jorbs-spire-mod') }
function global:cds { cd (Join-Path $ReposDirectory 'accessibility-insights-service') }
function global:cdweb { cd (Join-Path $ReposDirectory 'accessibility-insights-web') }
function global:cdwebp { cd (Join-Path $ReposDirectory 'accessibility-insights-web-private') }
function global:cdwin { cd (Join-Path $ReposDirectory 'accessibility-insights-windows') }
