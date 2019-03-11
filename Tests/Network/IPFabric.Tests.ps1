Param (
    [Parameter(Mandatory = $false)] [string] $TestenvConfFile,
    [Parameter(Mandatory = $false)] [string] $LogDir = 'pesterLogs',
    [Parameter(Mandatory = $false)] [bool] $PrepareEnv = $true,
    [Parameter(ValueFromRemainingArguments = $true)] $UnusedParams
)

. $PSScriptRoot\..\..\Utils\PowershellTools\Aliases.ps1
. $PSScriptRoot\..\..\Utils\PowershellTools\Init.ps1
. $PSScriptRoot\..\..\Utils\Testenv\Testbed.ps1

. $PSScriptRoot\..\..\PesterHelpers\PesterHelpers.ps1
. $PSScriptRoot\..\..\PesterLogger\PesterLogger.ps1
. $PSScriptRoot\..\..\PesterLogger\RemoteLogCollector.ps1

. $PSScriptRoot\..\..\TestConfigurationUtils.ps1

. $PSScriptRoot\..\..\Utils\WinContainers\Containers.ps1
. $PSScriptRoot\..\..\Utils\NetAdapterInfo\RemoteContainer.ps1
. $PSScriptRoot\..\..\Utils\Network\Connectivity.ps1
. $PSScriptRoot\..\..\Utils\DockerNetwork\Commands.ps1
. $PSScriptRoot\..\..\Utils\ComputeNode\Initialize.ps1
. $PSScriptRoot\..\..\Utils\ComputeNode\Configuration.ps1
. $PSScriptRoot\..\..\Utils\DockerNetwork\Commands.ps1

$ContrailProject = 'ci_tests_ip_fabric'
$ContainerID = 'jolly-lumberjack'
$ContainerNetInfo = $null

$NetworkPolicy = [NetworkPolicy]::new_PassAll('passallpolicy', $ContrailProject)
$VirtualNetwork = [VirtualNetwork]::New('testnet_fabric_ip', $ContrailProject, $null)
$VirtualNetwork.NetworkPolicysFqNames = @($NetworkPolicy.GetFqName())
$VirtualNetwork.EnableIpFabricForwarding()

function Get-ContainerSubnet {
    Param(
        [Parameter(Mandatory = $true)] [Hashtable] $IpInfo
    )

    function Convert-IpUInt32ToString {
        Param([Parameter(Mandatory = $true)] [uInt32] $Ip)

        [String[]] $Out = [String[]]::new(4)
        foreach ($i in (3..0)) {
            $Out[$i] = [convert]::ToString($Ip -band 255)
            $Ip = $ip -shr 8
        }
        return ($out -join '.')
    }

    function Convert-IpStringToUInt32 {
        Param([Parameter(Mandatory = $true)] [String] $Ip)

        [String[]] $IPAddressArr = $Ip.Split('.')
        [uInt32] $Out = 0
        foreach ($i in (3..0)) {
            $Out += ([convert]::ToUInt32($IPAddressArr[3 - $i]) -shl $i * 8)
        }
        return $Out
    }

    $NetPrefixMask = [uInt32]::MaxValue -shl (32 - $IpInfo.PrefixLength)
    $NetIp = Convert-IpStringToUInt32 -Ip $IpInfo.IPAddress
    $NetPrefix = $NetIp -band $NetPrefixMask
    $NetBroadcast = $NetPrefix + (-bnot $NetPrefixMask)

    # Code below generates subnet which contains last 8 addresses of dataplane network.
    # This subnet is used to create contrail network, so we needs at least 5 addresses:
    # Network address, Default gateway, Service Ip, At least one container IP, broadcast IP.
    # Network /29 is used, because /30 can have only 4 addresses.

    # Last IP in both networks is Broadcast. Usage of IPs in subnet:
    # 1  -  Network address (subnet prefix)
    # 2  -  Default gateway
    # 3  -  Service IP
    # 4  -  Not used
    # 5  -  Not used
    # 6  -  Not used
    # 7  -  Container IP (we use only one container in this test)
    # 8  -  Broadcast (same as broadcast in dataplane network)
    $SubnetPoolEnd = $NetBroadcast - 1
    $SubnetPoolBeg = $NetBroadcast - 1
    $SubnetDefaultGate = $NetBroadcast - 6
    $SubnetPrefix = $NetBroadcast - 7

    return [Subnet]::new(
        (Convert-IpUInt32ToString -Ip $SubnetPrefix),
        29, # Network prefix length, which allows 8 IP addresses
        (Convert-IpUInt32ToString -Ip $SubnetDefaultGate),
        (Convert-IpUInt32ToString -Ip $SubnetPoolBeg),
        (Convert-IpUInt32ToString -Ip $SubnetPoolEnd)
    )
}

Test-WithRetries 3 {
    Describe 'IP Fabric tests' -Tag Smoke, EnvSafe {
        Context "Gateway-less forwarding" {
            It 'Container can ping compute node in underlay network' {
                # TODO Move getting IP for interface to Testbed class
                $ComputeAddressInUnderlay = Invoke-Command -Session $Testenv.Testbeds[1].GetSession() -ScriptBlock {
                    (Get-NetIPAddress -InterfaceAlias $Using:Testenv.Testbeds[1].VHostName | Where-Object AddressFamily -eq 'IPv4').IpAddress
                }
                Test-Ping `
                    -Session $Testenv.Testbeds[0].GetSession() `
                    -SrcContainerName $ContainerID `
                    -DstContainerName "compute node in underlay network" `
                    -DstIP $ComputeAddressInUnderlay | Should Be 0
            }
        }

        BeforeAll {
            $Testenv = [Testenv]::New()
            $Testenv.Initialize($TestenvConfFile, $LogDir, $ContrailProject, $PrepareEnv)
            $BeforeAllStack = $Testenv.NewCleanupStack()

            $VirtualNetwork.Subnet = Get-ContainerSubnet -IpInfo $Testenv.Testbeds[1].DataIpInfo

            Write-Log "Creating network policy: $($NetworkPolicy.Name)"
            $Testenv.ContrailRepo.AddOrReplace($NetworkPolicy) | Out-Null
            $BeforeAllStack.Push($NetworkPolicy)

            Write-Log "Creating virtual network: $($VirtualNetwork.Name)"
            $Testenv.ContrailRepo.AddOrReplace($VirtualNetwork) | Out-Null
            $BeforeAllStack.Push($VirtualNetwork)

            Write-Log 'Creating docker networks'
            foreach ($Testbed in $Testenv.Testbeds) {
                Initialize-DockerNetworks `
                    -Session $Testbed.GetSession() `
                    -Networks @($VirtualNetwork) `
                    -TenantName $ContrailProject
                $BeforeAllStack.Push(${function:Remove-DockerNetwork}, @($Testbed, $VirtualNetwork.Name))
            }
        }

        AfterAll {
            $Testenv.Cleanup()
        }

        BeforeEach {
            $BeforeEachStack = $Testenv.NewCleanupStack()
            $BeforeEachStack.Push(${function:Merge-Logs}, @(, $Testenv.LogSources))
            $BeforeEachStack.Push(${function:Remove-AllContainers}, @(, $Testenv.Testbeds))

            Write-Log "Creating container: $ContainerID"
            New-Container `
                -Testbed $Testenv.Testbeds[0] `
                -NetworkName $VirtualNetwork.Name `
                -Name $ContainerID

            $ContainerNetInfo = Get-RemoteContainerNetAdapterInformation `
                -Session $Testenv.Testbeds[0].GetSession() -ContainerID $ContainerID
            Write-Log "IP of $($ContainerID): $($ContainerNetInfo.IPAddress)"

            $ContainersLogs = @(, (New-ContainerLogSource -Testbeds $Testenv.Testbeds[0] -ContainerNames $ContainerID))
            $BeforeEachStack.Push(${function:Merge-Logs}, @(, $ContainersLogs))
        }

        AfterEach {
            $BeforeEachStack.RunCleanup($Testenv.ContrailRepo)
        }
    }
}
