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

. $PSScriptRoot\..\..\Utils\Testenv\Testenv.ps1

. $PSScriptRoot\..\..\TestConfigurationUtils.ps1

. $PSScriptRoot\..\..\Utils\WinContainers\Containers.ps1
. $PSScriptRoot\..\..\Utils\NetAdapterInfo\RemoteContainer.ps1
. $PSScriptRoot\..\..\Utils\Network\Connectivity.ps1
. $PSScriptRoot\..\..\Utils\ComputeNode\Initialize.ps1
. $PSScriptRoot\..\..\Utils\ComputeNode\Service.ps1
. $PSScriptRoot\..\..\Utils\DockerNetwork\Commands.ps1

$ContrailProject = 'ci_tests_agentrestart'

$ContainerIds = @('jolly-lumberjack', 'juniper-tree', 'mountain-mama')
$ContainerNetInfos = @($null, $null, $null)

$Subnet = [Subnet]::new(
    '10.0.5.0',
    24,
    '10.0.5.1',
    '10.0.5.19',
    '10.0.5.83'
)
$VirtualNetwork = [VirtualNetwork]::New('testnet_agentrestart', $ContrailProject, $Subnet)

function Restart-Agent {
    Param (
        [Parameter(Mandatory = $true)] [Testbed] $Testbed
    )

    $ServiceName = Get-AgentServiceName
    Invoke-Command -Session $Testbed.GetSession() -ScriptBlock {
        Restart-Service $Using:ServiceName
    } | Out-Null
}

function Get-NumberOfStoredPorts {
    Param (
        [Parameter(Mandatory = $true)] [Testbed] $Testbed
    )

    $NumberOfStoredPorts = Invoke-Command -Session $Testbed.GetSession() -ScriptBlock {
        $PortsDir = 'C:\\ProgramData\\Contrail\\var\\lib\\contrail\\ports'
        if (-not (Test-Path $PortsDir)) {
            return 0
        }
        return @(Get-ChildItem -Path $PortsDir -File).Length
    }
    return $NumberOfStoredPorts
}

Test-WithRetries 3 {
    Describe 'Agent restart tests' -Tags Smoke, EnvSafe {
        It 'Ports are correctly restored after Agent restart' {
            Write-Log 'Testing ping before Agent restart...'
            Test-Ping `
                -Session $Testenv.Testbeds[0].GetSession() `
                -SrcContainerName $ContainerIds[0] `
                -DstContainerName $ContainerIds[1] `
                -DstIP $ContainerNetInfos[1].IPAddress | Should Be 0

            Get-NumberOfStoredPorts -Testbed $Testenv.Testbeds[0] | Should Be 1
            Restart-Agent -Testbed $Testenv.Testbeds[0]

            Write-Log 'Testing ping after Agent restart...'
            # On Windows Server 2019 it was observed that even though Restart-Service
            # returned, ports were not yet reloaded in agent, so the ping can fail for
            # the first time.
            $Retries = 5
            while (($Retries--) -gt 0) {
                $PingRes = Test-Ping `
                    -Session $Testenv.Testbeds[0].GetSession() `
                    -SrcContainerName $ContainerIds[0] `
                    -DstContainerName $ContainerIds[1] `
                    -DstIP $ContainerNetInfos[1].IPAddress
                if ($PingRes -eq 0) {
                    break
                }
            }
            $Retries | Should -Not -Be -1

            Write-Log "Creating container: $($ContainerIds[2])"
            New-Container `
                -Testbed $Testenv.Testbeds[1] `
                -NetworkName $VirtualNetwork.Name `
                -Name $ContainerIds[2]

            $ContainerNetInfos[2] = Get-RemoteContainerNetAdapterInformation `
                -Session $Testenv.Testbeds[1].GetSession() -ContainerID $ContainerIds[2]
            Write-Log "IP of $($ContainerIds[2]): $($ContainerNetInfos[2].IPAddress)"

            Get-NumberOfStoredPorts -Testbed $Testenv.Testbeds[0] | Should Be 1

            Write-Log 'Testing ping after Agent restart with new container...'
            Test-Ping `
                -Session $Testenv.Testbeds[0].GetSession() `
                -SrcContainerName $ContainerIds[0] `
                -DstContainerName $ContainerIds[2] `
                -DstIP $ContainerNetInfos[2].IPAddress | Should Be 0

            Stop-Container -Session $Testenv.Testbeds[0].GetSession() -NameOrId $ContainerIds[0]
            Get-NumberOfStoredPorts -Testbed $Testenv.Testbeds[0] | Should Be 0
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
            $BeforeEachStack.Push(${function:Start-AgentService}, @($Testenv.Testbeds[0]))
            $BeforeEachStack.Push(${function:Remove-AllContainers}, @(, $Testenv.Testbeds))
            Write-Log 'Creating containers'
            foreach ($i in 0..1) {
                Write-Log "Creating container: $($ContainerIds[$i])"
                New-Container `
                    -Testbed $Testenv.Testbeds[$i] `
                    -NetworkName $VirtualNetwork.Name `
                    -Name $ContainerIds[$i]

                $ContainerNetInfos[$i] = Get-RemoteContainerNetAdapterInformation `
                    -Session $Testenv.Testbeds[$i].GetSession() -ContainerID $ContainerIds[$i]
                Write-Log "IP of $($ContainerIds[$i]): $($ContainerNetInfos[$i].IPAddress)"
            }
            $ContainersLogs = @((New-ContainerLogSource -Testbeds $Testenv.Testbeds[0] -ContainerNames $ContainerIds[0]),
                (New-ContainerLogSource -Testbeds $Testenv.Testbeds[1] -ContainerNames $ContainerIds[1]))
            $BeforeEachStack.Push(${function:Merge-Logs}, @(, $ContainersLogs))
        }

        AfterEach {
            $BeforeEachStack.RunCleanup($Testenv.ContrailRepo)
        }
    }
}
