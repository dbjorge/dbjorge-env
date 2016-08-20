function PathStringWith ($OriginalPathString, $Term) {
    if ($OriginalPathString.Split("`n") -contains $Term) {
        $OriginalPathString
    } else {
        $OriginalPathString + ";$Term"
    }
}

$DesiredPathElements = @(
    'C:\Code\depot_tools'
)

foreach ($Element in $DesiredPathElements) {
    $env:PATH = PathStringWith $env:PATH $Element
}

New-Alias -Name 'which' -Value 'Get-Command'
New-Alias -Name 'subl' -Value 'C:\Program Files\Sublime Text 3\subl.exe'
New-Alias -Name 'code' -Value 'C:\Program Files (x86)\Microsoft VS Code\Code.exe'
