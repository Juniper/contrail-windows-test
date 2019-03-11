Param (
    [Parameter(Mandatory = $false)] [string] $TestenvConfFile,
    [Parameter(ValueFromRemainingArguments = $true)] $UnusedParams
)

. $PSScriptRoot\..\..\Utils\PowershellTools\Init.ps1

. $PSScriptRoot\..\..\Utils\Testenv\Configs.ps1
. $PSScriptRoot\..\..\Utils\Testenv\Testbed.ps1

. $PSScriptRoot\..\..\Utils\ComputeNode\Installation.ps1
. $PSScriptRoot\..\..\TestConfigurationUtils.ps1

. $PSScriptRoot\..\..\Utils\ContrailAPI\ContrailAPI.ps1
. $PSScriptRoot\..\..\Utils\TestCleanup\TestCleanup.ps1

Describe 'vTest scenarios' -Tag Smoke {
    It 'passes all vtest scenarios' {
        {
            Invoke-Command -Session $Testbed.GetSession() -ScriptBlock {
                Push-Location C:\Artifacts\
                .\vtest\all_tests_run.ps1 -VMSwitchName $Using:Testbed.VmSwitchName `
                    -TestsFolder vtest\tests
                Pop-Location
            }
        } | Should Not Throw
    }

    BeforeAll {
        $CleanupStack = [CleanupStack]::new()
        $Testbeds = [Testbed]::LoadFromFile($TestenvConfFile)
        $CleanupStack.Push( {Param([Testbed[]] $Testbeds) foreach ($Testbed in $Testbeds) { $Testbed.RemoveAllSessions() }}, @(, $Testbeds))
        $Testbed = $Testbeds[0]
        $SystemConfig = [SystemConfig]::LoadFromFile($TestenvConfFile)

        Install-Extension -Session $Testbed.GetSession()
        $CleanupStack.Push(${function:Uninstall-Extension}, @($Testbed))
        Install-Utils -Session $Testbed.GetSession()
        $CleanupStack.Push(${function:Uninstall-Utils}, @($Testbed))
        # TODO Make Enable-VRouterExtension an atomic operation and move this cleanup step after enabling vrouter
        $CleanupStack.Push(${function:Clear-TestConfiguration}, @($Testbed, $SystemConfig))
        Enable-VRouterExtension -Testbed $Testbed -SystemConfig $SystemConfig
    }

    AfterAll {
        $CleanupStack.RunCleanup($null)
    }
}
