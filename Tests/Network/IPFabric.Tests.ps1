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
. $PSScriptRoot\..\..\Utils\MultiNode\ContrailMultiNodeProvisioning.ps1
. $PSScriptRoot\..\..\Utils\DockerNetwork\Commands.ps1

$ContrailProject = 'ci_tests_ip_fabric'
$DockerImage = 'microsoft/windowsservercore'
$ContainerID = 'jolly-lumberjack'
$ContainerNetInfo = $null

$Subnet = [Subnet]::new(
    '172.16.0.128',
    28,
    '172.16.0.129',
    '172.16.0.130',
    '172.16.0.140'
)

$ComputeAddressInUnderlay = '172.16.0.2'
$NetworkPolicy = [NetworkPolicy]::new_PassAll('passallpolicy', $ContrailProject)
$VirtualNetwork = [VirtualNetwork]::New('testnet_fabric_ip', $ContrailProject, $Subnet)
$VirtualNetwork.NetworkPolicysFqNames = @($NetworkPolicy.GetFqName())
$VirtualNetwork.EnableIpFabricForwarding()

Test-WithRetries 3 {
    Describe 'IP Fabric tests' -Tag Smoke, EnvSafe {
        Context "Gateway-less forwarding" {
            It 'Container can ping compute node in underlay network' {
                Test-Ping `
                    -Session $Testenv.Sessions[0] `
                    -SrcContainerName $ContainerID `
                    -DstContainerName "compute node in underlay network" `
                    -DstIP $ComputeAddressInUnderlay | Should Be 0
            }
        }

        BeforeAll {
            $Testenv = [Testenv]::New()
            $Testenv.Initialize($TestenvConfFile, $LogDir, $ContrailProject, $PrepareEnv)
            $BeforeAllStack = $Testenv.NewCleanupStack()

            Write-Log "Creating network policy: $($NetworkPolicy.Name)"
            $Testenv.ContrailRepo.AddOrReplace($NetworkPolicy) | Out-Null
            $BeforeAllStack.Push($NetworkPolicy)

            Write-Log "Creating virtual network: $($VirtualNetwork.Name)"
            $Testenv.ContrailRepo.AddOrReplace($VirtualNetwork) | Out-Null
            $BeforeAllStack.Push($VirtualNetwork)

            Write-Log 'Creating docker networks'
            foreach ($Session in $Testenv.Sessions) {
                Initialize-DockerNetworks `
                    -Session $Session `
                    -Networks @($VirtualNetwork) `
                    -TenantName $ContrailProject
                $BeforeAllStack.Push(${function:Remove-DockerNetwork}, @($Session, $VirtualNetwork.Name))
            }
        }

        AfterAll {
            $Testenv.Cleanup()
        }

        BeforeEach {
            $BeforeEachStack = $Testenv.NewCleanupStack()
            $BeforeEachStack.Push(${function:Merge-Logs}, @(, $Testenv.LogSources))
            $BeforeEachStack.Push(${function:Remove-AllContainers}, @(, $Testenv.Sessions))

            Write-Log "Creating container: $ContainerID"
            New-Container `
                -Session $Testenv.Sessions[0] `
                -NetworkName $VirtualNetwork.Name `
                -Name $ContainerID `
                -Image $DockerImage

            $ContainerNetInfo = Get-RemoteContainerNetAdapterInformation `
                -Session $Testenv.Sessions[0] -ContainerID $ContainerID
            Write-Log "IP of $($ContainerID): $($ContainerNetInfo.IPAddress)"

            $ContainersLogs = @(, (New-ContainerLogSource -Testbeds $Testenv.Testbeds[0] -ContainerNames $ContainerID))
            $BeforeEachStack.Push(${function:Merge-Logs}, @(, $ContainersLogs))
        }

        AfterEach {
            $BeforeEachStack.RunCleanup($Testenv.ContrailRepo)
        }
    }
}
