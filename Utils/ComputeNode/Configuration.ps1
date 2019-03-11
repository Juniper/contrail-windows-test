. $PSScriptRoot\..\..\Utils\PowershellTools\Init.ps1
. $PSScriptRoot\..\..\Utils\PowershellTools\Invoke-CommandWithFunctions.ps1

. $PSScriptRoot\..\Testenv\Configs.ps1

. $PSScriptRoot\..\..\Utils\NetAdapterInfo\RemoteHost.ps1
. $PSScriptRoot\..\..\PesterLogger\RemoteLogCollector.ps1


function Get-DefaultConfigDir {
    return "C:\ProgramData\Contrail\etc\contrail"
}

function Get-DefaultCNMPluginsConfigPath {
    return Join-Path $(Get-DefaultConfigDir) "contrail-cnm-plugin.conf"
}

function Get-DefaultAgentConfigPath {
    return Join-Path $(Get-DefaultConfigDir) "contrail-vrouter-agent.conf"
}

function Get-DefaultNodeMgrsConfigPath {
    return Join-Path $(Get-DefaultConfigDir) "contrail-vrouter-nodemgr.conf"
}

function New-CNMPluginConfigFile {
    Param (
        [Parameter(Mandatory = $true)] [Testbed] $Testbed,
        [Parameter(Mandatory = $false)] [OpenStackConfig] $OpenStackConfig,
        [Parameter(Mandatory = $true)] [ControllerConfig] $ControllerConfig
    )

    Write-Log 'Creating CNM plugin config file'

    $ConfigPath = Get-DefaultCNMPluginsConfigPath

    $Config = @"
[DRIVER]
Adapter=$($Testbed.DataAdapterName)
ControllerIP=$( $ControllerConfig.MgmtAddress )
ControllerPort=8082

[LOGGING]
LogLevel=Debug

[AUTH]
AuthMethod=$( $ControllerConfig.AuthMethod )
"@
    if ($OpenStackConfig) {
        $Config += @"


[KEYSTONE]
Os_auth_url=$( $OpenStackConfig.AuthUrl() )
Os_username=$( $OpenStackConfig.Username )
Os_tenant_name=$( $OpenStackConfig.Project )
Os_password=$( $OpenStackConfig.Password )
Os_token=
"@
    }

    Invoke-Command -Session $Testbed.GetSession() -ScriptBlock {
        Set-Content -Path $Using:ConfigPath -Value $Using:Config
    }
}

function Get-NodeManagementIP {
    Param(
        [Parameter(Mandatory = $true)] [Testbed] $Testbed
    )
    return Invoke-Command -Session $Testbed.GetSession() -ScriptBlock {
        Get-NetIPAddress |
        Where-Object InterfaceAlias -like $Using:Testbed.MgmtAdapterName |
        Where-Object AddressFamily -eq IPv4 |
        Select-Object -ExpandProperty IPAddress
    }
}

function New-NodeMgrConfigFile {
    Param (
        [Parameter(Mandatory = $true)] [Testbed] $Testbed,
        [Parameter(Mandatory = $true)] [string] $ControllerIP
    )

    Write-Log 'Creating node manager config file'

    $ConfigPath = Get-DefaultNodeMgrsConfigPath
    $LogPath = Get-NodeMgrLogPath

    $HostIP = Get-NodeManagementIP -Testbed $Testbed

    $Config = @"
[DEFAULTS]
log_local=1
log_level=SYS_DEBUG
log_file=$LogPath
hostip=$HostIP

[COLLECTOR]
server_list=${ControllerIP}:8086

[SANDESH]
introspect_ssl_enable=False
sandesh_ssl_enable=False
"@

    Invoke-Command -Session $Testbed.GetSession() -ScriptBlock {
        Set-Content -Path $Using:ConfigPath -Value $Using:Config
    }
}

function Get-AdaptersInfo {
    Param (
        [Parameter(Mandatory = $true)] [Testbed] $Testbed
    )
    # Gather information about testbed's network adapters
    $HNSTransparentAdapter = Get-RemoteNetAdapterInformation `
            -Session $Testbed.GetSession() `
            -AdapterName $Testbed.VHostName

    $PhysicalAdapter = Get-RemoteNetAdapterInformation `
            -Session $Testbed.GetSession() `
            -AdapterName $Testbed.DataAdapterName

    return @{
        "VHostIfIndex" = $HNSTransparentAdapter.ifIndex;
        "PhysIfName"   = $PhysicalAdapter.ifName
    }
}

#Functions executed in the remote machine to create Agent's config file.
function Get-VHostConfiguration {
    Param (
        [Parameter(Mandatory = $true)] [string] $IfIndex
    )
    $IP = (Get-NetIPAddress -ifIndex $IfIndex -AddressFamily IPv4).IPAddress
    $PrefixLength = (Get-NetIPAddress -ifIndex $IfIndex -AddressFamily IPv4).PrefixLength
    $Gateway = (Get-NetIPConfiguration -InterfaceIndex $IfIndex).IPv4DefaultGateway
    $GatewayConfig = if ($Gateway) { "gateway=$( $Gateway.NextHop )" } else { "" }

    return @{
        "IP"            = $IP;
        "PrefixLength"  = $PrefixLength;
        "GatewayConfig" = $GatewayConfig
    }
}

function Get-AgentConfig {
    Param (
        [Parameter(Mandatory = $true)] [string] $ControllerCtrlIp,
        [Parameter(Mandatory = $true)] [string] $VHostIfIndex,
        [Parameter(Mandatory = $true)] [string] $PhysIfName
    )
    $VHostConfguration = Get-VHostConfiguration -IfIndex $VHostIfIndex

    return @"
[DEFAULT]
platform=windows

[CONTROL-NODE]
servers=$ControllerCtrlIp

[DNS]
dns_client_port=53
servers=$($ControllerCtrlIp):53

[VIRTUAL-HOST-INTERFACE]
name=
ip=$( $VHostConfguration.IP )/$( $VHostConfguration.PrefixLength )
$( $VHostConfguration.GatewayConfig )
physical_interface=$PhysIfName
"@
}

function New-AgentConfigFile {
    Param (
        [Parameter(Mandatory = $true)] [Testbed] $Testbed,
        [Parameter(Mandatory = $true)] [ControllerConfig] $ControllerConfig,
        [Parameter(Mandatory = $true)] [SystemConfig] $SystemConfig
    )

    Write-Log 'Creating agent config files'

    $AdaptersInfo = Get-AdaptersInfo -Testbed $Testbed
    $AgentConfigPath = Get-DefaultAgentConfigPath

    Invoke-CommandWithFunctions `
        -Functions @("Get-VHostConfiguration", "Get-AgentConfig") `
        -Session $Testbed.GetSession() `
        -ScriptBlock {
            # Save file with prepared config
            $ConfigFileContent = Get-AgentConfig `
                -ControllerCtrlIp $Using:ControllerConfig.CtrlAddress `
                -VHostIfIndex $Using:AdaptersInfo.VHostIfIndex `
                -PhysIfName $Using:AdaptersInfo.PhysIfName

            Set-Content -Path $Using:AgentConfigPath -Value $ConfigFileContent
        }
}

function New-ComputeNodeLogSources {
    Param([Parameter(Mandatory = $false)] [Testbed[]] $Testbeds)
    [LogSource[]] $LogSources = @()
    $LogSources += Get-ServicesLogPaths | ForEach-Object {
        New-FileLogSource -Path $_ -Testbeds $Testbeds
    }
    $LogSources += New-EventLogLogSource -Testbeds $Testbeds -EventLogName "Application" -EventLogSource "Docker"
    return $LogSources
}
