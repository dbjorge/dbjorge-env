Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Modelled after the current state of https://github.com/PowerShell/PowerShell/issues/6201
function Convert-TextFile {
    [CmdletBinding(DefaultParameterSetName='Path')]
    [OutputType($null)]
    param(
        [Parameter(
            Mandatory,
            ParameterSetName  = 'Path',
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [ValidateNotNullOrEmpty()]
        [SupportsWildcards()]
        [string[]]$Path,
     
        [Parameter(
            Mandatory,
            ParameterSetName = 'LiteralPath',
            Position = 0,
            ValueFromPipelineByPropertyName
        )]
        [ValidateNotNullOrEmpty()]
        [Alias('PSPath')]
        [string[]]$LiteralPath,

        [Parameter(Position=1)]
        [ValidateSet('Lf','CrLf','Windows','Unix')]
        [string]
        $LineEnding = 'Lf',

        [Parameter(Position=2)]
        [System.Text.Encoding]
        $FromEncoding = [System.Text.Encoding]::Default,

        [Parameter(Position=3)]
        [System.Text.Encoding]
        $ToEncoding = [System.Text.Encoding]::Default,

        [Parameter(Position=4)]
        [switch]
        $NoNewline,

        [Parameter(Position=5)]
        [switch]
        $AsByteStream
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $resolvedPaths = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
        } elseif ($PSCmdlet.ParameterSetName -eq 'LiteralPath') {
            $resolvedPaths = Resolve-Path -LiteralPath $LiteralPath | Select-Object -ExpandProperty Path
        }

        $delimiter = if ($LineEnding -in ('Lf', 'Unix')) { "`n" } else { "`r`n" };

        foreach ($resolvedPath in $resolvedPaths) {
            $fullContentInMemory = (Get-Content -LiteralPath $resolvedPath -Encoding:$FromEncoding)
            $convertedContent = $fullContentInMemory -join $delimiter;
            if (-not $NoNewline) { $convertedContent += $delimiter; }
            $convertedContent | Set-Content -NoNewline -LiteralPath $resolvedPath -Encoding:$ToEncoding -AsByteStream:$AsByteStream
        }
    }

}

Export-ModuleMember -Function @(
    'Convert-TextFile'
)