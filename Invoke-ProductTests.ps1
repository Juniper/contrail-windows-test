Param(
    [Parameter(Mandatory = $false)] [string] $TestRootDir = ".",
    [Parameter(Mandatory = $true)] [string] $TestReportDir,
    [Parameter(Mandatory = $true)] [string] $TestenvConfFile,
    [Parameter(Mandatory = $false)] [switch] $UseExistingServices,
    [Parameter(Mandatory = $false)] [switch] $SmokeTestsOnly
)

. $PSScriptRoot\TestRunner\TestRunner.ps1

if (-not (Test-Path $TestReportDir)) {
    New-Item -ItemType Directory -Path $TestReportDir | Out-Null
}

$DetailedLogsDir = Join-Path $TestReportDir "detailed_logs"
$CnmPluginJUnitLogsOutputDir = Join-Path $TestReportDir "cnm_plugin_junit_test_logs"

$PesterOutReportDir = Join-Path $TestReportDir "raw_NUnit"
$PesterOutReportPath = Join-Path $PesterOutReportDir "report.xml"

Invoke-IntegrationAndFunctionalTests `
    -TestRootDir $TestRootDir `
    -TestenvConfFile $TestenvConfFile `
    -PesterOutReportPath $PesterOutReportPath `
    -DetailedLogsOutputDir $DetailedLogsDir `
    -AdditionalJUnitsDir $CnmPluginJUnitLogsOutputDir `
    -UseExistingServices:$UseExistingServices `
    -SmokeTestsOnly:$SmokeTestsOnly
