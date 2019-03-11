Param (
    [Parameter(Mandatory = $false)] [string] $TestenvConfFile,
    [Parameter(Mandatory = $false)] [string] $LogDir = 'pesterLogs',
    [Parameter(Mandatory = $false)] [bool] $PrepareEnv = $true,
    [Parameter(ValueFromRemainingArguments = $true)] $UnusedParams
)

. $PSScriptRoot\..\..\Utils\PowershellTools\Init.ps1
. $PSScriptRoot\..\..\Utils\PowershellTools\Aliases.ps1

. $PSScriptRoot\..\..\PesterHelpers\PesterHelpers.ps1
. $PSScriptRoot\..\..\PesterLogger\PesterLogger.ps1
. $PSScriptRoot\..\..\PesterLogger\RemoteLogCollector.ps1

. $PSScriptRoot\..\..\Utils\Testenv\Testenv.ps1

. $PSScriptRoot\..\..\TestConfigurationUtils.ps1

. $PSScriptRoot\..\..\Utils\ComputeNode\Initialize.ps1
. $PSScriptRoot\..\..\Utils\ComputeNode\Service.ps1
. $PSScriptRoot\..\..\Utils\ComputeNode\Configuration.ps1
. $PSScriptRoot\..\..\Utils\MultiNode\ContrailMultiNodeProvisioning.ps1

$ContrailProject = 'ci_tests_nodemanager'

# TODO: This variable is not passed down to New-NodeMgrConfig in ComponentsInstallation.ps1
#       Should be refactored.
$LogPath = Get-NodeMgrLogPath

function Clear-NodeMgrLogs {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session
    )

    Invoke-Command -Session $Session -ScriptBlock {
        if (Test-Path -Path $Using:LogPath) {
            Remove-Item $Using:LogPath -Force
        }
    }
}

function Test-NodeMgrLogs {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session
    )

    $Res = Invoke-Command -Session $Session -ScriptBlock {
        return Test-Path -Path $Using:LogPath
    }

    return $Res
}

function Test-NodeMgrConnectionWithController {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session,
        [Parameter(Mandatory = $true)] [string] $ControllerIP
    )

    $TestbedHostname = Invoke-Command -Session $Session -ScriptBlock {
        hostname
    }
    $Out = Invoke-RestMethod ("http://$($ControllerIP):8089/Snh_ShowCollectorServerReq?")
    $OurNode = $Out.ShowCollectorServerResp.generators.list.GeneratorSummaryInfo.source | Where-Object '#text' -Like $TestbedHostname

    return [bool]($OurNode)
}

function Test-ControllerReceivesNodeStatus {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session
    )

    # TODO

    return $true
}

Describe 'Node manager' -Tags Smoke, EnvSafe {
    It 'starts' {
        $Sess = $Testenv.Testbeds[0].GetSession()
        Eventually {
            Test-NodeMgrLogs -Session $Sess | Should Be True
        } -Duration 60
    }

    It 'connects to controller' {
        $Sess = $Testenv.Testbeds[0].GetSession()
        Eventually {
            Test-NodeMgrConnectionWithController `
                -Session $Sess `
                -ControllerIP $Testenv.Controller.MgmtAddress | Should Be True
        } -Duration 60
    }

    It "sets node state as 'Up'" -Pending {
        $Sess = $Testenv.Testbeds[0].GetSession()
        Eventually {
            Test-ControllerReceivesNodeStatus -Session $Sess | Should Be True
        } -Duration 60
    }

    AfterEach {
        Merge-Logs -LogSources $Testenv.LogSources
    }

    BeforeAll {
        $Testenv = [Testenv]::New()
        $Testenv.Initialize($TestenvConfFile, $LogDir, $ContrailProject, $PrepareEnv)
    }

    AfterAll {
        $Testenv.Cleanup()
    }
}
