Param (
    [Parameter(Mandatory = $false)] [string] $TestenvConfFile,
    [Parameter(Mandatory = $false)] [string] $LogDir = 'pesterLogs',
    [Parameter(ValueFromRemainingArguments = $true)] $UnusedParams
)

. $PSScriptRoot\..\..\Utils\PowershellTools\Aliases.ps1
. $PSScriptRoot\..\..\Utils\PowershellTools\Init.ps1

. $PSScriptRoot\..\..\Utils\ContrailAPI\ContrailAPI.ps1
. $PSScriptRoot\..\..\Utils\Testenv\Testbed.ps1

. $PSScriptRoot\..\..\TestConfigurationUtils.ps1

. $PSScriptRoot\..\..\PesterHelpers\PesterHelpers.ps1

. $PSScriptRoot\..\..\PesterLogger\PesterLogger.ps1
. $PSScriptRoot\..\..\PesterLogger\RemoteLogCollector.ps1

. $PSScriptRoot\..\..\Utils\ComputeNode\Initialize.ps1
. $PSScriptRoot\..\..\Utils\Testenv\Testenv.ps1

. $PSScriptRoot\..\..\Utils\WinContainers\Containers.ps1
. $PSScriptRoot\..\..\Utils\ComputeNode\Installation.ps1
. $PSScriptRoot\..\..\Utils\ComputeNode\Configuration.ps1
. $PSScriptRoot\..\..\Utils\ComputeNode\Service.ps1
. $PSScriptRoot\..\..\Utils\NetAdapterInfo\RemoteContainer.ps1
. $PSScriptRoot\..\..\Utils\NetAdapterInfo\RemoteHost.ps1
. $PSScriptRoot\..\..\Utils\Network\Connectivity.ps1

$ContrailProject = 'ci_tests_utils'

$ContainerIds = @('jolly-lumberjack', 'juniper-tree')
$ContainerNetInfos = @($null, $null)

$DockerImages = @('python-http', $null)

$Subnet = [Subnet]::new(
    "10.0.0.0",
    24,
    "10.0.0.1",
    "10.0.0.100",
    "10.0.0.200"
)
$VirtualNetwork = [VirtualNetwork]::New('testnet_utils', $ContrailProject, $Subnet)

Test-WithRetries 3 {
    Describe 'Single compute node protocol tests with utils' -Tag 'Utils' {

        function Initialize-ContainersConnection {
            Param (
                [Parameter(Mandatory = $true)] $VMNetInfo,
                [Parameter(Mandatory = $true)] $VHostInfo,
                [Parameter(Mandatory = $true)] $Container1NetInfo,
                [Parameter(Mandatory = $true)] $Container2NetInfo,
                [Parameter(Mandatory = $true)] [PSSessionT] $Session
            )

            Write-Log $('Setting a connection between ' + $Container1NetInfo.MACAddress + `
                    ' and ' + $Container2NetInfo.MACAddress + '...')

            Invoke-Command -Session $Session -ScriptBlock {
                vif.exe --add $Using:VMNetInfo.IfName --mac $Using:VMNetInfo.MACAddress --vrf 0 --type physical

                vif.exe --add $Using:VHostInfo.IfName --mac $Using:VHostInfo.MACAddress --vrf 0 --type vhost --xconnect $Using:VMNetInfo.IfName

                vif.exe --add $Using:Container1NetInfo.IfName --mac $Using:Container1NetInfo.MACAddress --vrf 1 --type virtual
                vif.exe --add $Using:Container2NetInfo.IfName --mac $Using:Container2NetInfo.MACAddress --vrf 1 --type virtual

                nh.exe --create 1 --vrf 1 --type 2 --l2 --oif $Using:Container1NetInfo.IfIndex
                nh.exe --create 2 --vrf 1 --type 2 --l2 --oif $Using:Container2NetInfo.IfIndex
                nh.exe --create 3 --vrf 1 --type 6 --l2 --cen --cni 1 --cni 2

                rt.exe -c -v 1 -f 1 -e ff:ff:ff:ff:ff:ff -n 3
                rt.exe -c -v 1 -f 1 -e $Using:Container1NetInfo.MACAddress -n 1
                rt.exe -c -v 1 -f 1 -e $Using:Container2NetInfo.MACAddress -n 2
            }
        }

        It 'Ping succeeds' {
            Test-Ping `
                -Session $Testbed.GetSession() `
                -SrcContainerName $ContainerIds[0] `
                -DstContainerName $ContainerIds[1] `
                -DstIP $ContainerNetInfos[1].IPAddress | Should Be 0

            Test-Ping `
                -Session $Testbed.GetSession() `
                -SrcContainerName $ContainerIds[1] `
                -DstContainerName $ContainerIds[0] `
                -DstIP $ContainerNetInfos[0].IPAddress | Should Be 0
        }

        It 'Ping with big buffer succeeds' {
            Test-Ping `
                -Session $Testbed.GetSession() `
                -SrcContainerName $ContainerIds[0] `
                -DstContainerName $ContainerIds[1] `
                -DstIP $ContainerNetInfos[1].IPAddress `
                -BufferSize 3500 | Should Be 0

            Test-Ping `
                -Session $Testbed.GetSession() `
                -SrcContainerName $ContainerIds[1] `
                -DstContainerName $ContainerIds[0] `
                -DstIP $ContainerNetInfos[0].IPAddress `
                -BufferSize 3500 | Should Be 0
        }

        It 'TCP connection works' {
            $ContainerId = $ContainerIds[1]
            $ContainerIp = $ContainerNetInfos[0].IPAddress
            Invoke-Command -Session $Testbed.GetSession() -ScriptBlock {
                docker exec $Using:ContainerId powershell "Invoke-WebRequest -UseBasicParsing -Uri http://${Using:ContainerIP}:8080/ -ErrorAction Continue" | Out-Null
                return $LASTEXITCODE
            } | Should Be 0

        }

        BeforeEach {
            $BeforeEachStack = $Testenv.NewCleanupStack()
            $BeforeEachStack.Push(${function:Merge-Logs}, @(, $Testenv.LogSources))

            Write-Log "Creating virtual network: $($VirtualNetwork.Name)"
            $Testenv.ContrailRepo.AddOrReplace($VirtualNetwork) | Out-Null
            $BeforeEachStack.Push($VirtualNetwork)

            New-CNMPluginConfigFile -Testbed $Testbed `
                -OpenStackConfig $Testenv.OpenStack `
                -ControllerConfig $Testenv.Controller

            Initialize-CnmPluginAndExtension -Testbed $Testbed `
                -SystemConfig $Testenv.System `

            $BeforeEachStack.Push(${function:Clear-TestConfiguration}, @($Testbed, $Testenv.System))

            New-DockerNetwork -Session $Testbed.GetSession() `
                -TenantName $ContrailProject `
                -Name $VirtualNetwork.Name `
                -Subnet "$( $Subnet.IpPrefix )/$( $Subnet.IpPrefixLen )"

            $BeforeEachStack.Push(${function:Remove-AllContainers}, @($Testbed))

            foreach ($i in 0..1) {
                Write-Log "Creating container: $($ContainerIds[$i])"
                New-Container `
                    -Testbed $Testbed `
                    -NetworkName $VirtualNetwork.Name `
                    -Name $ContainerIds[$i] `
                    -Image $DockerImages[$i]

                $ContainerNetInfos[$i] = Get-RemoteContainerNetAdapterInformation `
                    -Session $Testbed.GetSession() -ContainerID $ContainerIds[$i]
                Write-Log "IP of $($ContainerIds[$i]): $($ContainerNetInfos[$i].IPAddress)"
            }

            Write-Log 'Getting VM NetAdapter Information'
            $VMNetInfo = Get-RemoteNetAdapterInformation -Session $Testbed.GetSession() `
                -AdapterName $Testbed.DataAdapterName

            Write-Log 'Getting vHost NetAdapter Information'
            $VHostInfo = Get-RemoteNetAdapterInformation -Session $Testbed.GetSession() `
                -AdapterName $Testbed.VHostName

            Initialize-ContainersConnection -VMNetInfo $VMNetInfo -VHostInfo $VHostInfo `
                -Container1NetInfo $ContainerNetInfos[0] -Container2NetInfo $ContainerNetInfos[1] `
                -Session $Testbed.GetSession()

            $ContainersLogs = @(New-ContainerLogSource -Testbeds $Testenv.Testbeds[0] -ContainerNames $ContainerIds[0], $ContainerIds[1])
            $BeforeEachStack.Push(${function:Merge-Logs}, @(, $ContainersLogs))
        }

        AfterEach {
            $BeforeEachStack.RunCleanup($Testenv.ContrailRepo)
        }

        BeforeAll {
            $Testenv = [Testenv]::New()
            $Testenv.Initialize($TestenvConfFile, $LogDir, $ContrailProject, $true)

            $BeforeAllStack = $Testenv.NewCleanupStack()

            $Testbed = $Testenv.Testbeds[0]

            Install-Utils -Session $Testbed.GetSession()
            $BeforeAllStack.Push(${function:Uninstall-Utils}, @($Testbed))
            Test-IfUtilsCanLoadDLLs -Session $Testbed.GetSession()

            Stop-NodeMgrService -Session $Testbed.GetSession()
            Stop-CNMPluginService -Session $Testbed.GetSession()
            Stop-AgentService -Session $Testbed.GetSession()
            Disable-VRouterExtension -Testbed $Testbed -SystemConfig $TestEnv.System
        }

        AfterAll {
            $Testenv.Cleanup()
        }
    }
}
