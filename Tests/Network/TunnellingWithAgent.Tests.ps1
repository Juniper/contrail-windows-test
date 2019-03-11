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

$ContrailProject = 'ci_tests_tunneling'

$DockerImages = @('python-http', $null)

$ContainersIDs = @('jolly-lumberjack', 'juniper-tree')
$ContainerNetInfos = @($null, $null)

$Subnet = [Subnet]::new(
    '10.0.5.0',
    24,
    '10.0.5.1',
    '10.0.5.19',
    '10.0.5.83'
)
$VirtualNetwork = [VirtualNetwork]::New('testnet_tunneling', $ContrailProject, $Subnet)

function Get-MaxIPv4DataSizeForMTU {
    Param ([Parameter(Mandatory = $true)] [Int] $MTU)
    $MinimalIPHeaderSize = 20
    return $MTU - $MinimalIPHeaderSize
}

function Get-MaxICMPDataSizeForMTU {
    Param ([Parameter(Mandatory = $true)] [Int] $MTU)
    $ICMPHeaderSize = 8
    return $(Get-MaxIPv4DataSizeForMTU -MTU $MTU) - $ICMPHeaderSize
}

function Get-MaxUDPDataSizeForMTU {
    Param ([Parameter(Mandatory = $true)] [Int] $MTU)
    $UDPHeaderSize = 8
    return $(Get-MaxIPv4DataSizeForMTU -MTU $MTU) - $UDPHeaderSize
}

function Get-VrfStats {
    Param ([Parameter(Mandatory = $true)] [Testbed] $Testbed)

    # NOTE: we are assuming that there will be only one vif with index == 2.
    #       Indices 0 and 1 are reserved, so the first available is index 2.
    #       This is consistent - for now. It used to be that only index 0 was reserved, so it may
    #       change in the future.
    #       We could get this index by using other utils and doing a bunch of filtering, but
    #       let's do it when the time comes.
    $VifIdx = 2
    $Stats = Invoke-Command -Session $Testbed.GetSession() -ScriptBlock {
        $Out = $(vrfstats --get $Using:VifIdx)
        $PktCountMPLSoUDP = [regex]::new('Udp Mpls Tunnels ([0-9]+)').Match($Out[3]).Groups[1].Value
        $PktCountMPLSoGRE = [regex]::new('Gre Mpls Tunnels ([0-9]+)').Match($Out[3]).Groups[1].Value
        $PktCountVXLAN = [regex]::new('Vxlan Tunnels ([0-9]+)').Match($Out[3]).Groups[1].Value
        return @{
            MPLSoUDP = $PktCountMPLSoUDP
            MPLSoGRE = $PktCountMPLSoGRE
            VXLAN    = $PktCountVXLAN
        }
    }
    Write-Log "vrfstats for vif $VifIdx : $($Stats | Out-String)"
    return $Stats
}

Test-WithRetries 3 {
    Describe 'Tunneling with Agent tests' -Tags Smoke, EnvSafe {

        #
        #               !!!!!! IMPORTANT: DEBUGGING/DEVELOPING THESE TESTS !!!!!!
        #
        # tl;dr: "fresh" controller uses MPLSoGRE by default. But when someone logs in via WebUI for
        # the first time, it changes to MPLSoUDP. You have been warned.
        #
        # Logging into WebUI for the first time is known to cause problems.
        # When someone logs into webui for the first time, it suddenly realizes that its default
        # encap priorities list is different than the one on the controller. It causes a cascade of
        # requests from WebUI to config node, that will change the tunneling method.
        #
        # When debugging, make sure that the encapsulation method specified in webui
        # (under Configure/Infrastructure/Global Config/Virtual Routers/Encapsulation Priority Order)
        # matches the one that is applied using ContrailNM in code below (Config node REST API).
        # Do it especially when logging in via WebUI for the first time.
        #

        foreach ($TunnelingMethod in @('MPLSoGRE', 'MPLSoUDP', 'VXLAN')) {
            Context "Tunneling $TunnelingMethod" {
                BeforeEach {
                    $GlobalVrouterConfig = [GlobalVrouterConfig]::New(@($TunnelingMethod))
                    $Testenv.ContrailRepo.Set($GlobalVrouterConfig)
                }

                It 'Uses specified tunneling method' {

                    $StatsBefore = Get-VrfStats -Testbed $Testenv.Testbeds[0]

                    Test-Ping `
                        -Session $Testenv.Testbeds[0].GetSession() `
                        -SrcContainerName $ContainersIDs[0] `
                        -DstContainerName $ContainersIDs[1] `
                        -DstIP $ContainerNetInfos[1].IPAddress | Should Be 0

                    $StatsAfter = Get-VrfStats -Testbed $Testenv.Testbeds[0]
                    $StatsAfter[$TunnelingMethod] | Should BeGreaterThan $StatsBefore[$TunnelingMethod]
                }

                It 'ICMP - Ping between containers on separate compute nodes succeeds' {
                    Test-Ping `
                        -Session $Testenv.Testbeds[0].GetSession() `
                        -SrcContainerName $ContainersIDs[0] `
                        -DstContainerName $ContainersIDs[1] `
                        -DstIP $ContainerNetInfos[1].IPAddress | Should Be 0

                    Test-Ping `
                        -Session $Testenv.Testbeds[1].GetSession() `
                        -SrcContainerName $ContainersIDs[1] `
                        -DstContainerName $ContainersIDs[0] `
                        -DstIP $ContainerNetInfos[0].IPAddress | Should Be 0
                }

                It 'TCP - HTTP connection between containers on separate compute nodes succeeds' {
                    Test-TCP `
                        -Session $Testenv.Testbeds[1].GetSession() `
                        -SrcContainerName $ContainersIDs[1] `
                        -DstContainerName $ContainersIDs[0] `
                        -DstIP $ContainerNetInfos[0].IPAddress | Should Be 0
                }

                It 'UDP - sending message between containers on separate compute nodes succeeds' {
                    $MyMessage = 'We are Tungsten Fabric. We come in peace.'

                    Test-UDP `
                        -ListenerContainerSession $Testenv.Testbeds[0].GetSession() `
                        -ListenerContainerName $ContainersIDs[0] `
                        -ListenerContainerIP $ContainerNetInfos[0].IPAddress `
                        -ClientContainerSession $Testenv.Testbeds[1].GetSession() `
                        -ClientContainerName $ContainersIDs[1] `
                        -Message $MyMessage | Should Be $true
                }

                It 'IP fragmentation - ICMP - Ping with big buffer succeeds' {
                    $Container1MsgFragmentationThreshold = Get-MaxICMPDataSizeForMTU -MTU $ContainerNetInfos[0].MtuSize
                    $Container2MsgFragmentationThreshold = Get-MaxICMPDataSizeForMTU -MTU $ContainerNetInfos[1].MtuSize

                    $SrcContainers = @($ContainersIDs[0], $ContainersIDs[1])
                    $DstContainers = @($ContainersIDs[1], $ContainersIDs[0])
                    $DstIPs = @($ContainerNetInfos[1].IPAddress, $ContainerNetInfos[0].IPAddress)
                    $BufferSizes = @($Container1MsgFragmentationThreshold, $Container2MsgFragmentationThreshold)

                    foreach ($ContainerIdx in 0..1) {
                        $BufferSizeLargerBeforeTunneling = $BufferSizes[$ContainerIdx] + 1
                        $BufferSizeLargerAfterTunneling = $BufferSizes[$ContainerIdx] - 1
                        foreach ($BufferSize in @($BufferSizeLargerBeforeTunneling, $BufferSizeLargerAfterTunneling)) {
                            Test-Ping `
                                -Session $Testenv.Testbeds[$ContainerIdx].GetSession() `
                                -SrcContainerName $SrcContainers[$ContainerIdx] `
                                -DstContainerName $DstContainers[$ContainerIdx] `
                                -DstIP $DstIPs[$ContainerIdx] `
                                -BufferSize $BufferSize | Should Be 0
                        }
                    }
                }

                It 'IP fragmentation - UDP - sending big buffer succeeds' {
                    $MsgFragmentationThreshold = Get-MaxUDPDataSizeForMTU -MTU $ContainerNetInfos[0].MtuSize

                    $MessageLargerBeforeTunneling = 'a' * $($MsgFragmentationThreshold + 1)
                    $MessageLargerAfterTunneling = 'a' * $($MsgFragmentationThreshold - 1)
                    foreach ($Message in @($MessageLargerBeforeTunneling, $MessageLargerAfterTunneling)) {
                        Test-UDP `
                            -ListenerContainerSession $Testenv.Testbeds[0].GetSession() `
                            -ListenerContainerName $ContainersIDs[0] `
                            -ListenerContainerIP $ContainerNetInfos[0].IPAddress `
                            -ClientContainerSession $Testenv.Testbeds[1].GetSession() `
                            -ClientContainerName $ContainersIDs[1] `
                            -Message $Message | Should Be $true
                    }
                }

                # NOTE: There is no TCPoIP fragmentation test, because it auto-adjusts segment size,
                #       so it would always pass.
            }
        }

        BeforeAll {
            $Testenv = [Testenv]::New()
            $Testenv.Initialize($TestenvConfFile, $LogDir, $ContrailProject, $PrepareEnv)

            $BeforeAllStack = $Testenv.NewCleanupStack()

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
            Write-Log 'Creating containers'
            foreach ($i in 0..1) {
                Write-Log "Creating container: $($ContainersIDs[$i])"
                New-Container `
                    -Testbed $Testenv.Testbeds[$i] `
                    -NetworkName $VirtualNetwork.Name `
                    -Name $ContainersIDs[$i] `
                    -Image $DockerImages[$i]

                $ContainerNetInfos[$i] = Get-RemoteContainerNetAdapterInformation `
                    -Session $Testenv.Testbeds[$i].GetSession() -ContainerID $ContainersIDs[$i]
                Write-Log "IP of $($ContainersIDs[$i]): $($ContainerNetInfos[$i].IPAddress)"
            }
            $ContainersLogs = @((New-ContainerLogSource -Testbeds $Testenv.Testbeds[0] -ContainerNames $ContainersIDs[0]),
                (New-ContainerLogSource -Testbeds $Testenv.Testbeds[1] -ContainerNames $ContainersIDs[1]))
            $BeforeEachStack.Push(${function:Merge-Logs}, @(, $ContainersLogs))
        }

        AfterEach {
            $BeforeEachStack.RunCleanup($Testenv.ContrailRepo)
        }
    }
}
