Param (
    [Parameter(ValueFromRemainingArguments=$true)] $AdditionalParams
)

$AllScripts = Get-ChildItem -Recurse -Include "*.ps1"
$TestCases = $AllScripts | ForEach-Object { @{File = Resolve-Path -Relative $_} }

# Based on https://github.com/steviecoaster/PSSysadminToolkit/blob/d8afede4862f78608d1d0d385f693fb21583bf3b/Test/ScriptValidation.Tests.ps1#L18
# by steviecoaster - MIT license

Describe "Powershell syntax validation" -Tags CISelfcheck, Unit {
    It "<File> should be valid PowerShell" -TestCases $TestCases {
        param($File)

        $FileContents = Get-Content -Path $File -ErrorAction Stop
        $Errors = $null
        [System.Management.Automation.PSParser]::Tokenize($FileContents, [ref]$Errors) > $null

        # Filter out false-positives
        # `Unable to find type [class name]` happens due to us relying on dot-sourcing of
        # PowerShell classes, which is heavily import-order dependent.
        $FilteredErrors = $Errors | Where-Object Message -notlike "Unable to find type*"

        $FilteredErrors | Should -HaveCount 0
    }
}
