# From https://github.com/stuartleeks/posh-dnvm/blob/master/RunPester.ps1

function GetLineNumber($stackTrace){
	if($stackTrace -match "at line: (\d*)"){
		$matches[1];
	} else {
		$null
	}
}
function GetFileName($stackTrace){
	if($stackTrace -match "at line: (?:\d*) in (.*)\n"){
		$matches[1];
	} else {
		$null
	}	
}
function FormatResult ($result){
	process {
		if ($null -eq $_ -or $null -eq $_.StackTrace) { return }

		$lineNumber = GetLineNumber $_.StackTrace
		$relativeFile = GetFileName $_.StackTrace
		if ($null -eq $relativeFile) { return }
		$absoluteFile = $relativeFile | Resolve-Path -Relative
		$collapsedMessage = $_.FailureMessage -replace "`n"," "
		$testDescription = "$($_.Describe):$($_.Name)"
		"$absoluteFile;$lineNumber;${testDescription}:$collapsedMessage"
	}
}
Write-Output "Running tests..."
$results = Invoke-Pester -PassThru -PesterOption (New-PesterOption -IncludeVSCodeMarker)
$results.TestResult | Where-Object { -not $_.Passed} | FormatResult
Write-Output "Done"