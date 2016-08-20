Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function PathStringWith ($OriginalPathString, $Term) {
    if ($OriginalPathString.Split(";") -contains $Term) {
        $OriginalPathString
    } else {
        $OriginalPathString + ";$Term"
    }
}

function Register-PathElement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,
                   ValueFromPipeline=$true,
                   Position=0)]
        [string[]]
        $PathElement,

        [Parameter(Mandatory=$false,
                   Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]
        $PathEnvironmentVariable = 'PATH',

        [Parameter(Mandatory=$false,
                   Position=2)]
        [ValidateNotNull()]
        [System.EnvironmentVariableTarget]
        $Scope = [System.EnvironmentVariableTarget]::Process
    )
    begin {
        $OriginalValue = [Environment]::GetEnvironmentVariable($PathEnvironmentVariable)
        $UpdatedValue = $OriginalValue
    }
    process {
        foreach ($Element in $PathElement) {
            $UpdatedValue = PathStringWith $UpdatedValue $Element
        }
    }
    end {
        if ($OriginalValue -ne $UpdatedValue) {
            [System.Environment]::SetEnvironmentVariable($PathEnvironmentVariable, $UpdatedValue, $Scope)
        }
    }
}

Export-ModuleMember -Function @(
    'Register-PathElement'
)