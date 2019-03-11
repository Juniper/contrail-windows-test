. $PSScriptRoot\Invoke-PesterTests.ps1

. $PSScriptRoot\..\PesterHelpers\PesterHelpers.ps1

function Invoke-IntegrationAndFunctionalTests {
    Param (
        [Parameter(Mandatory = $false)] [String] $TestRootDir = ".",
        [Parameter(Mandatory = $true)] [String] $TestenvConfFile,
        [Parameter(Mandatory = $true)] [String] $PesterOutReportPath,
        [Parameter(Mandatory = $true)] [String] $DetailedLogsOutputDir,
        [Parameter(Mandatory = $true)] [String] $AdditionalJUnitsDir,
        [Parameter(Mandatory = $false)] [switch] $UseExistingServices,
        [Parameter(Mandatory = $false)] [switch] $SmokeTestsOnly
    )
    # TODO: Maybe we should collect codecov statistics similarly in the future?

    # TODO2: Changing AdditionalParams force us to modify all the tests that use it -> maybe find a better way to pass them?

    $AdditionalParams = @{
        TestenvConfFile     = $TestenvConfFile
        LogDir              = $DetailedLogsOutputDir
        AdditionalJUnitsDir = $AdditionalJUnitsDir
        PrepareEnv          = -not $UseExistingServices
    }

    # Empty lists defaults to all tests.
    $IncludeTags = @()
    if ($SmokeTestsOnly) {
        $IncludeTags += "Smoke"
    }

    $Results = Invoke-PesterTests -TestRootDir $TestRootDir -ReportPath $PesterOutReportPath `
        -ExcludeTags CISelfcheck -IncludeTags $IncludeTags -AdditionalParams $AdditionalParams
    if (-not (Test-ResultsWithRetries -Results $Results.TestResult)) {
        throw "Some tests failed"
    }
}
