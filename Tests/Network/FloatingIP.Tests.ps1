Param (
    [Parameter(Mandatory = $false)] [string] $TestenvConfFile,
    [Parameter(Mandatory = $false)] [string] $LogDir = 'pesterLogs',
    [Parameter(Mandatory = $false)] [bool] $PrepareEnv = $true,
    [Parameter(ValueFromRemainingArguments = $true)] $UnusedParams
)

. $PSScriptRoot\..\..\Utils\ContrailAPI\ContrailAPI.ps1

. $PSScriptRoot\..\..\Utils\Testenv\Testbed.ps1

. $PSScriptRoot\..\..\PesterLogger\PesterLogger.ps1
. $PSScriptRoot\..\..\PesterLogger\RemoteLogCollector.ps1

. $PSScriptRoot\..\..\TestConfigurationUtils.ps1

. $PSScriptRoot\..\..\Utils\WinContainers\Containers.ps1
. $PSScriptRoot\..\..\Utils\Network\Connectivity.ps1
. $PSScriptRoot\..\..\Utils\ComputeNode\Initialize.ps1
. $PSScriptRoot\..\..\Utils\ComputeNode\Configuration.ps1
. $PSScriptRoot\..\..\Utils\DockerNetwork\Commands.ps1
. $PSScriptRoot\..\..\Utils\MultiNode\ContrailMultiNodeProvisioning.ps1

. $PSScriptRoot\..\..\Utils\TestCleanup\TestCleanup.ps1

$ContrailProject = 'ci_tests_floatingip'

$NetworkPolicy = [NetworkPolicy]::new_PassAll('passallpolicy', $ContrailProject)

$ClientNetworkSubnet = [Subnet]::new(
    '10.1.1.0',
    24,
    '10.1.1.1',
    '10.1.1.11',
    '10.1.1.100'
)
$ClientNetwork = [VirtualNetwork]::New('network_floatingip_client', $ContrailProject, $ClientNetworkSubnet)
$ClientNetwork.NetworkPolicysFqNames = @($NetworkPolicy.GetFqName())

$ServerNetworkSubnet = [Subnet]::new(
    '10.2.2.0',
    24,
    '10.2.2.1',
    '10.2.2.11',
    '10.2.2.100'
)
$ServerNetwork = [VirtualNetwork]::New('network_floatingip_server', $ContrailProject, $ServerNetworkSubnet)
$ServerNetwork.NetworkPolicysFqNames = @($NetworkPolicy.GetFqName())

$Networks = @($ClientNetwork, $ServerNetwork)

$ServerFloatingIpPool = [FloatingIpPool]::New('test_pool', $ServerNetwork.GetFqName())
$ServerFloatingIp = [FloatingIp]::New('test_fip', $ServerFloatingIpPool.GetFqName(), '10.2.2.10')

$ContainerImage = 'microsoft/windowsservercore'
$ContainerClientID = 'fip-client'
$ContainerServerID = 'fip-server'

Describe 'Floating IP' -Tags Smoke, EnvSafe {
    Context 'Multinode' {
        Context '2 networks' {
            It 'ICMP works' {
                Test-Ping `
                    -Session $Testenv.Sessions[0] `
                    -SrcContainerName $ContainerClientID `
                    -DstIP $ServerFloatingIp.Address | Should Be 0
            }

            BeforeAll {
                $InnerBeforeAllStack = $Testenv.NewCleanupStack()

                Write-Log "Creating network policy: $($NetworkPolicy.Name)"
                $Testenv.ContrailRepo.AddOrReplace($NetworkPolicy) | Out-Null
                $InnerBeforeAllStack.Push($NetworkPolicy)

                Write-Log "Creating virtual network: $($ClientNetwork.Name)"
                $Testenv.ContrailRepo.AddOrReplace($ClientNetwork) | Out-Null
                $InnerBeforeAllStack.Push($ClientNetwork)

                Write-Log "Creating virtual network: $($ServerNetwork.Name)"
                $Testenv.ContrailRepo.AddOrReplace($ServerNetwork) | Out-Null
                $InnerBeforeAllStack.Push($ServerNetwork)

                Write-Log "Creating floating IP pool: $($ServerFloatingIpPool.Name)"
                $Testenv.ContrailRepo.AddOrReplace($ServerFloatingIpPool) | Out-Null
                $InnerBeforeAllStack.Push($ServerFloatingIpPool)

                foreach ($Session in $Testenv.Sessions) {
                    Initialize-DockerNetworks `
                        -Session $Session `
                        -Networks $Networks `
                        -TenantName $ContrailProject
                    $InnerBeforeAllStack.Push(${function:Remove-DockerNetwork}, @($Session, $ServerNetwork.Name))
                    $InnerBeforeAllStack.Push(${function:Remove-DockerNetwork}, @($Session, $ClientNetwork.Name))
                }
            }

            AfterAll {
                $InnerBeforeAllStack.RunCleanup($Testenv.ContrailRepo)
            }

            BeforeEach {
                $BeforeEachStack = $Testenv.NewCleanupStack()
                $BeforeEachStack.Push(${function:Merge-Logs}, @(, $Testenv.LogSources))
                $BeforeEachStack.Push(${function:Remove-AllContainers}, @(, $Testenv.Sessions))

                Write-Log 'Creating containers'
                Write-Log "Creating container: $ContainerClientID"
                New-Container `
                    -Session $Testenv.Sessions[0] `
                    -NetworkName $ClientNetwork.Name `
                    -Name $ContainerClientID `
                    -Image $ContainerImage

                Write-Log 'Creating containers'
                Write-Log "Creating container: $ContainerServerID"
                New-Container `
                    -Session $Testenv.Sessions[1] `
                    -NetworkName $ServerNetwork.Name `
                    -Name $ContainerServerID `
                    -Image $ContainerImage

                $ContainersLogs = @((New-ContainerLogSource -Testbeds $Testenv.Testbeds[0] -ContainerNames $ContainerClientID),
                    (New-ContainerLogSource -Testbeds $Testenv.Testbeds[1] -ContainerNames $ContainerServerID))
                $BeforeEachStack.Push(${function:Merge-Logs}, @(, $ContainersLogs))

                $VirtualNetworkRepo = [VirtualNetworkRepo]::new($Testenv.MultiNode.ContrailRestApi)
                $ServerFloatingIp.PortFqNames = $VirtualNetworkRepo.GetPorts($ServerNetwork)

                Write-Log "Creating floating IP: $($ServerFloatingIp.Name)"
                $Testenv.ContrailRepo.AddOrReplace($ServerFloatingIp)
                $BeforeEachStack.Push($ServerFloatingIp)
            }

            AfterEach {
                $BeforeEachStack.RunCleanup($Testenv.ContrailRepo)
            }
        }

        BeforeAll {
            $Testenv = [Testenv]::New()
            $Testenv.Initialize($TestenvConfFile, $LogDir, $ContrailProject, $PrepareEnv)
        }

        AfterAll {
            $Testenv.Cleanup()
        }
    }
}
