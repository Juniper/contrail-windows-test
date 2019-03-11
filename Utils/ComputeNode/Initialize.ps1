. $PSScriptRoot\..\Testenv\Testenv.ps1

. $PSScriptRoot\..\..\PesterLogger\PesterLogger.ps1
. $PSScriptRoot\..\..\TestConfigurationUtils.ps1
. $PSScriptRoot\Configuration.ps1
. $PSScriptRoot\Installation.ps1
. $PSScriptRoot\Service.ps1
. $PSScriptRoot\..\DockerNetwork\Commands.ps1

function Set-ConfAndLogDir {
    Param (
        [Parameter(Mandatory = $true)] [Testbed[]] $Testbeds
    )
    $ConfigDirPath = Get-DefaultConfigDir
    $LogDirPath = Get-ComputeLogsDir

    foreach ($Testbed in $Testbeds) {
        Invoke-Command -Session $Testbed.GetSession() -ScriptBlock {
            New-Item -ItemType Directory -Path $using:ConfigDirPath -Force | Out-Null
            New-Item -ItemType Directory -Path $using:LogDirPath -Force | Out-Null
        } | Out-Null
    }
}

function Initialize-ComputeNode {
    Param (
        [Parameter(Mandatory = $true)] [Testbed] $Testbed,
        [Parameter(Mandatory = $true)] [Testenv] $Configs,
        [Parameter(Mandatory = $true)] [CleanupStack] $CleanupStack
    )
    Write-Log "Installing components on testbed: $($Testbed.GetSession().ComputerName)"
    Install-Components `
        -Testbed $Testbed `
        -CleanupStack $CleanupStack

    Write-Log "Initializing components on testbed: $($Testbed.GetSession().ComputerName)"
    Initialize-ComputeServices `
        -Testbed $Testbed `
        -SystemConfig $Configs.System `
        -OpenStackConfig $Configs.OpenStack `
        -ControllerConfig $Configs.Controller `
        -CleanupStack $CleanupStack
}

function Initialize-ComputeServices {
    Param (
        [Parameter(Mandatory = $true)] [Testbed] $Testbed,
        [Parameter(Mandatory = $true)] [SystemConfig] $SystemConfig,
        [Parameter(Mandatory = $false)] [OpenStackConfig] $OpenStackConfig,
        [Parameter(Mandatory = $true)] [ControllerConfig] $ControllerConfig,
        [Parameter(Mandatory = $true)] [CleanupStack] $CleanupStack
    )

    New-NodeMgrConfigFile `
        -Testbed $Testbed  `
        -ControllerIP $ControllerConfig.MgmtAddress

    New-CNMPluginConfigFile `
        -Testbed $Testbed `
        -OpenStackConfig $OpenStackConfig `
        -ControllerConfig $ControllerConfig

    Initialize-CnmPluginAndExtension `
        -Testbed $Testbed `
        -SystemConfig $SystemConfig
    $CleanupStack.Push(${function:Remove-CnmPluginAndExtension}, @($Testbed, $SystemConfig))

    New-AgentConfigFile -Testbed $Testbed `
        -ControllerConfig $ControllerConfig `
        -SystemConfig $SystemConfig

    Start-AgentService -Session $Testbed.GetSession()
    $CleanupStack.Push(${function:Stop-AgentService}, @($Testbed))
    Start-NodeMgrService -Session $Testbed.GetSession()
    $CleanupStack.Push(${function:Stop-NodeMgrService}, @($Testbed))
}
