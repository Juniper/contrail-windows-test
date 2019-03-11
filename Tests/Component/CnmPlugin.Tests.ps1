Param (
    [Parameter(Mandatory = $false)] [string] $TestenvConfFile,
    [Parameter(Mandatory = $false)] [string] $LogDir = "pesterLogs",
    [Parameter(Mandatory = $false)] [string] $AdditionalJUnitsDir = "AdditionalJUnitLogs",
    [Parameter(ValueFromRemainingArguments = $true)] $UnusedParams
)

. $PSScriptRoot\..\..\Utils\PowershellTools\Aliases.ps1
. $PSScriptRoot\..\..\Utils\PowershellTools\Invoke-NativeCommand.ps1

. $PSScriptRoot\..\..\Utils\Testenv\Testbed.ps1

. $PSScriptRoot\..\..\PesterLogger\PesterLogger.ps1
. $PSScriptRoot\..\..\PesterLogger\RemoteLogCollector.ps1

# TODO: This path should probably come from TestenvConfFile.
$RemoteTestModulesDir = "C:\Artifacts\cnm-plugin"

function Find-CnmPluginTests {
    Param (
        [Parameter(Mandatory = $true)] [Testbed] $Testbed,
        [Parameter(Mandatory = $true)] [string] $RemoteSearchDir
    )

    return Invoke-Command -Session $Testbed.GetSession() {
        Get-ChildItem -Recurse -Filter "*.test.exe" -Path $Using:RemoteSearchDir `
            | Select-Object BaseName, FullName
    }
}

function Invoke-CnmPluginUnitTest {
    Param (
        [Parameter(Mandatory = $true)] [Testbed] $Testbed,
        [Parameter(Mandatory = $true)] [string] $TestModulePath,
        [Parameter(Mandatory = $true)] [string] $RemoteJUnitOutputDir
    )

    $Command = @($TestModulePath, "--ginkgo.succinct", "--ginkgo.failFast")
    $Command = $Command -join " "

    $Res = Invoke-NativeCommand -CaptureOutput -AllowNonZero -Session $Testbed.GetSession() {
        Push-Location $Using:RemoteJUnitOutputDir
        try {
            Invoke-Expression -Command $Using:Command
        }
        finally {
            Pop-Location
        }
    }

    Write-Log $Res.Output

    return $Res.ExitCode
}

function Save-CnmPluginUnitTestReport {
    Param (
        [Parameter(Mandatory = $true)] [Testbed] $Testbed,
        [Parameter(Mandatory = $true)] [String] $RemoteJUnitDir,
        [Parameter(Mandatory = $true)] [string] $LocalJUnitDir
    )

    if (-not (Test-Path $LocalJUnitDir)) {
        New-Item -ItemType Directory -Path $LocalJUnitDir | Out-Null
    }

    $FoundRemoteJUnitReports = Invoke-Command -Session $Testbed.GetSession() -ScriptBlock {
        Get-ChildItem -Filter "*_junit.xml" -Recurse -Path $Using:RemoteJUnitDir
    }

    Copy-Item $FoundRemoteJUnitReports.FullName -Destination $LocalJUnitDir -FromSession $Testbed.GetSession()
}

Describe "CNM Plugin" -Tags Smoke, EnvSafe {
    BeforeAll {
        $Testbeds = [Testbed]::LoadFromFile($TestenvConfFile)
        $Testbed = $Testbeds[0]

        Initialize-PesterLogger -OutDir $LogDir

        $FoundTestModules = @(Find-CnmPluginTests -RemoteSearchDir $RemoteTestModulesDir -Testbed $Testbed)
        if (0 -eq $FoundTestModules.Count) {
            throw [System.IO.FileNotFoundException]::new(
                "Could not find any file matching '*.test.exe' in $RemoteTestModulesDir directory."
            )
        }

        Write-Log "Discovered test modules: $($FoundTestModules.BaseName)"
    }

    AfterAll {
        foreach ($Testbed in $Testbeds) {
            $Testbed.RemoveAllSessions()
        }
    }

    foreach ($TestModule in $FoundTestModules) {
        Context "Tests for module in $($TestModule.BaseName)" {
            It "passes tests" {
                $TestResult = Invoke-CnmPluginUnitTest -Testbed $Testbed -TestModulePath $TestModule.FullName -RemoteJUnitOutputDir $RemoteTestModulesDir
                $TestResult | Should Be 0
            }

            AfterEach {
                Save-CnmPluginUnitTestReport -Testbed $Testbed -RemoteJUnitDir $RemoteTestModulesDir -LocalJUnitDir $AdditionalJUnitsDir
            }
        }
    }
}
