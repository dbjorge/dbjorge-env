function Set-LocationEx
{
    param([string]$Path, [switch]$PassThru)

    $ActualPath = $Path

    # expand CMD-style environment variables
    while ($ActualPath -like '*%*%*')
    {
        $null = $ActualPath -match '^(?<start>.*?)%(?<var>.*?)%(?<end>.*)$'
        $ActualPath = $matches["start"] + (gi "env:$($matches[""var""])").Value + $matches["end"]
    }

    # always use canonical casing, even if input didn't
    Set-Location -Path $ActualPath
    $ActualPath = $pwd.Path
    $gitFriendlyLocation = cmd /c "pushd %systemdrive%\&popd&cd"
    Set-Location -Path $gitFriendlyLocation -PassThru:$PassThru

    if ($gitFriendlyLocation -cne $ActualPath)
    {
        Write-Warning "Fixing case to: ""$gitFriendlyLocation"""
    }
}

Export-ModuleMember -Function @('Set-LocationEx')