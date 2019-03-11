Param (
    [Parameter(Mandatory = $false)] [string] $TestenvConfFile,
    [Parameter(Mandatory = $false)] [string] $LogDir = 'pesterLogs',
    [Parameter(Mandatory = $false)] [bool] $PrepareEnv = $true,
    [Parameter(ValueFromRemainingArguments = $true)] $UnusedParams
)

. $PSScriptRoot\..\..\Utils\PowershellTools\Aliases.ps1
. $PSScriptRoot\..\..\Utils\PowershellTools\Init.ps1

. $PSScriptRoot\..\..\Utils\ContrailAPI\ContrailAPI.ps1

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
. $PSScriptRoot\..\..\Utils\MultiNode\ContrailMultiNodeProvisioning.ps1
. $PSScriptRoot\..\..\Utils\DockerNetwork\Commands.ps1

$ContrailProject = 'ci_tests_security'

$NetworkPolicy = [NetworkPolicy]::new_PassAll('passallpolicy', $ContrailProject)

$ServerNetworkSubnet = [Subnet]::new(
    '10.2.2.0',
    24,
    '10.2.2.1',
    '10.2.2.11',
    '10.2.2.100'
)

$ClientNetworkSubnet = [Subnet]::new(
    '10.1.1.0',
    24,
    '10.1.1.1',
    '10.1.1.11',
    '10.1.1.100'
)

$GlobalTag = [Tag]::new('application', 'testapp')
$ServerNetworkTag = [Tag]::new('tier', 'server_testnet_security')
$ClientNetworkTag = [Tag]::new('tier', 'client_testnet_security')

$ServerNetwork = [VirtualNetwork]::New('ci_testnet_security_server', $ContrailProject, $ServerNetworkSubnet)
$ServerNetwork.NetworkPolicysFqNames = @($NetworkPolicy.GetFqName())
$ServerNetwork.AddTags(@($GlobalTag.GetFqName(), $ServerNetworkTag.GetFqName()))

$ServerEndPoint = [TagsFirewallRuleEndpoint]::new(@($GlobalTag.GetName(), $ServerNetworkTag.GetName()))

$ClientNetwork = [VirtualNetwork]::New('ci_testnet_security_client', $ContrailProject, $ClientNetworkSubnet)
$ClientNetwork.NetworkPolicysFqNames = @($NetworkPolicy.GetFqName())
$ClientNetwork.AddTags(@($GlobalTag.GetFqName(), $ClientNetworkTag.GetFqName()))

$ClientEndpoint = [TagsFirewallRuleEndpoint]::new(@($GlobalTag.GetName(), $ClientNetworkTag.GetName()))

$Networks = @($ServerNetwork, $ClientNetwork)

$Containers = @{
    'server' = @{
        'Name'         = 'jolly-lumberjack'
        'Image'        = 'python-http'
        'NetInfo'      = $null
        'HostSession'  = $null
        'Testbed'      = $null
        'Network'      = $ServerNetwork
    }
    'client' = @{
        'Name'         = 'juniper-tree'
        'Image'        = 'microsoft/windowsservercore'
        'NetInfo'      = $null
        'HostSession'  = $null
        'Testbed'      = $null
        'Network'      = $ClientNetwork
    }
}

function Initialize-Security {
    Param (
        [Parameter(Mandatory = $true)] [CleanUpStack] $CleanupStack,
        [Parameter(Mandatory = $true)] [FirewallRule[]] $FirewallRules,
        [Parameter(Mandatory = $true)] [ContrailRepo] $ContrailRepo
    )

    $FirewallPolicy = [FirewallPolicy]::new('test-firewall-policy')

    foreach ($FirewallRule in $FirewallRules) {
        $I = $FirewallRules.IndexOf($FirewallRule)
        Write-Log "Creating firewall rule: $($FirewallRule.Name)"
        $ContrailRepo.AddOrReplace($FirewallRule) | Out-Null
        $FirewallPolicy.AddFirewallRule($FirewallRule.GetFqName(), $I)
        $CleanupStack.Push($FirewallRule)
    }

    Write-Log "Creating firewall policy: $($FirewallPolicy.Name)"
    $ContrailRepo.AddOrReplace($FirewallPolicy) | Out-Null
    $CleanupStack.Push($FirewallPolicy)

    $ApplicationPolicy = [ApplicationPolicy]::new('test-app-policy', @($FirewallPolicy.GetFqName()), @($GlobalTag.GetFqName()))
    Write-Log "Creating application policy: $($ApplicationPolicy.Name)"
    $ContrailRepo.AddOrReplace($ApplicationPolicy) | Out-Null
    $CleanupStack.Push($ApplicationPolicy)
}

function Test-Security {
    Param (
        [Parameter(Mandatory = $true)] [FirewallRule[]] $TestRules,
        [Parameter(Mandatory = $true)] [Testenv] $Testenv,
        [Parameter(Mandatory = $true)] [ScriptBlock] $TestInvocation
    )

    $TestCleanupStack = $Testenv.NewCleanupStack()

    Initialize-Security `
        -CleanupStack $TestCleanupStack `
        -FirewallRules $TestRules `
        -ContrailRepo $Testenv.ContrailRepo | Out-Null

    try {
        Invoke-Command $TestInvocation
    }
    finally {
        $TestCleanupStack.RunCleanup($Testenv.ContrailRepo)
    }
}

Test-WithRetries 1 {
    Describe 'Contrail-Security tests' -Tag EnvSafe {
        Context 'TCP' {
            It 'Passes all the traffic' {
                $TestRules = @(
                    [FirewallRule]::new(
                        'test-firewall-rule-tcp-pass-biway-full',
                        [BiFirewallDirection]::new(),
                        [SimplePassRuleAction]::new(),
                        [FirewallService]::new_TCP_Full(),
                        $ServerEndPoint,
                        $ClientEndpoint
                    )
                )

                Test-Security -TestRules $TestRules -Testenv $Testenv {
                    Test-TCP `
                        -Session $Containers.client.HostSession `
                        -SrcContainerName $Containers.client.Name `
                        -DstContainerName $Containers.server.Name `
                        -DstIP $Containers.server.NetInfo.IPAddress | Should Be 0
                }
            }

            It 'Denies all the traffic' {
                $TestRules = @(
                    [FirewallRule]::new(
                        'test-firewall-rule-tcp-deny-biway-full',
                        [BiFirewallDirection]::new(),
                        [SimpleDenyRuleAction]::new(),
                        [FirewallService]::new_TCP_Full(),
                        $ServerEndPoint,
                        $ClientEndpoint
                    )
                )

                Test-Security -TestRules $TestRules -Testenv $Testenv {
                    { Test-TCP `
                        -Session $Containers.client.HostSession `
                        -SrcContainerName $Containers.client.Name `
                        -DstContainerName $Containers.server.Name `
                        -DstIP $Containers.server.NetInfo.IPAddress } | Should -Throw "Invoke-WebRequest"
                }
            }
        }

        Context 'UDP' {
            It 'Denies traffic on range of udp ports' {
                $TestRules = @(
                    [FirewallRule]::new(
                        'test-firewall-rule-udp-deny-uniway-range',
                        [BiFirewallDirection]::new(),
                        [SimpleDenyRuleAction]::new(),
                        [FirewallService]::new_UDP_range(1111, 2222),
                        $ServerEndPoint,
                        $ClientEndpoint
                    ),
                    [FirewallRule]::new(
                        'test-firewall-rule-udp-pass-biway-full',
                        [BiFirewallDirection]::new(),
                        [SimplePassRuleAction]::new(),
                        [FirewallService]::new_UDP_Full(),
                        $ServerEndPoint,
                        $ClientEndpoint
                    )
                )

                Test-Security -TestRules $TestRules -Testenv $Testenv {
                    Test-UDP `
                        -ListenerContainerSession $Containers.server.HostSession `
                        -ListenerContainerName $Containers.server.Name `
                        -ListenerContainerIP $Containers.server.NetInfo.IPAddress `
                        -ClientContainerSession $Containers.client.HostSession `
                        -ClientContainerName $Containers.client.Name `
                        -Message 'With contrail-security i feel safe now.' `
                        -UDPServerPort 1111 `
                        -UDPClientPort 2222 | Should Be $false

                    Test-UDP `
                        -ListenerContainerSession $Containers.server.HostSession `
                        -ListenerContainerName $Containers.server.Name `
                        -ListenerContainerIP $Containers.server.NetInfo.IPAddress `
                        -ClientContainerSession $Containers.client.HostSession `
                        -ClientContainerName $Containers.client.Name `
                        -Message 'With contrail-security i feel safe now.' `
                        -UDPServerPort 3333 `
                        -UDPClientPort 4444 | Should Be $true
                }
            }
        }

        BeforeAll {
            $Testenv = [Testenv]::New()
            $Testenv.Initialize($TestenvConfFile, $LogDir, $ContrailProject, $PrepareEnv)

            $Containers.client.HostSession = $Testenv.Sessions[0]
            $Containers.client.Testbed = $Testenv.Testbeds[0]
            $Containers.server.HostSession = $Testenv.Sessions[1]
            $Containers.server.Testbed = $Testenv.Testbeds[1]

            $BeforeAllStack = $Testenv.NewCleanupStack()

            Write-Log "Adding global application tag: $($GlobalTag.GetName())"
            $Testenv.ContrailRepo.AddOrReplace($GlobalTag) | Out-Null
            $BeforeAllStack.Push($GlobalTag)

            Write-Log "Creating network policy: $($NetworkPolicy.Name)"
            $Testenv.ContrailRepo.AddOrReplace($NetworkPolicy) | Out-Null
            $BeforeAllStack.Push($NetworkPolicy)

            Write-Log "Adding tag $($ClientNetworkTag.GetName()) for $($ClientNetwork.Name)"
            $Testenv.ContrailRepo.AddOrReplace($ClientNetworkTag)
            $BeforeAllStack.Push($ClientNetworkTag)

            Write-Log "Creating virtual network: $($ClientNetwork.Name)"
            $Testenv.ContrailRepo.AddOrReplace($ClientNetwork) | Out-Null
            $BeforeAllStack.Push($ClientNetwork)

            Write-Log "Adding tag $($ServerNetworkTag.GetName()) for $($ServerNetwork.Name)"
            $Testenv.ContrailRepo.AddOrReplace($ServerNetworkTag)
            $BeforeAllStack.Push($ServerNetworkTag)

            Write-Log "Creating virtual network: $($ServerNetwork.Name)"
            $Testenv.ContrailRepo.AddOrReplace($ServerNetwork) | Out-Null
            $BeforeAllStack.Push($ServerNetwork)

            Write-Log 'Creating docker networks'
            foreach ($Session in $Testenv.Sessions) {
                Initialize-DockerNetworks `
                    -Session $Session `
                    -Networks $Networks  `
                    -TenantName $ContrailProject
                $BeforeAllStack.Push(${function:Remove-DockerNetwork}, @($Session, $ClientNetwork.Name))
                $BeforeAllStack.Push(${function:Remove-DockerNetwork}, @($Session, $ServerNetwork.Name))
            }
        }

        AfterAll {
            $Testenv.Cleanup()
        }

        BeforeEach {
            $BeforeEachStack = $Testenv.NewCleanupStack()
            $BeforeEachStack.Push(${function:Merge-Logs}, @(, $Testenv.LogSources))
            $BeforeEachStack.Push(${function:Remove-AllContainers}, @(, $Testenv.Sessions))
            $ContainersLogs = @()
            Write-Log 'Creating containers'
            foreach ($Key in $Containers.Keys) {
                $Container = $Containers[$Key]
                Write-Log "Creating container: $($Container.Name)"
                New-Container `
                    -Session $Container.HostSession `
                    -NetworkName $Container.Network.Name `
                    -Name $Container.Name `
                    -Image $Container.Image

                $Container.NetInfo = Get-RemoteContainerNetAdapterInformation `
                    -Session $Container.HostSession -ContainerID $Container.Name
                $ContainersLogs += New-ContainerLogSource -Testbeds $Container.Testbed -ContainerNames $Container.Name
                Write-Log "IP of $($Container.Name): $($Container.NetInfo.IPAddress)"
            }
            $BeforeEachStack.Push(${function:Merge-Logs}, @(, $ContainersLogs))
        }

        AfterEach {
            $BeforeEachStack.RunCleanup($Testenv.ContrailRepo)
        }
    }
}
