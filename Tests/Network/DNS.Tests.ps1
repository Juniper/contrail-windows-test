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

. $PSScriptRoot\..\..\Utils\ComputeNode\TestsRequirements.ps1
. $PSScriptRoot\..\..\Utils\WinContainers\Containers.ps1
. $PSScriptRoot\..\..\Utils\NetAdapterInfo\RemoteContainer.ps1
. $PSScriptRoot\..\..\Utils\ComputeNode\Initialize.ps1
. $PSScriptRoot\..\..\Utils\DockerNetwork\Commands.ps1
. $PSScriptRoot\..\..\Utils\ComputeNode\Configuration.ps1

. $PSScriptRoot\..\..\Utils\TestCleanup\TestCleanup.ps1

$ContrailProject = 'ci_tests_dns'

$ContainersIDs = @('jolly-lumberjack', 'juniper-tree')

$Subnet = [Subnet]::new(
    '10.0.5.0',
    24,
    '10.0.5.1',
    '10.0.5.19',
    '10.0.5.83'
)
$VirtualNetwork = [VirtualNetwork]::New('testnet_dns', $ContrailProject, $Subnet)

$TenantDNSServerAddress = '10.0.5.80'

$VirtualDNSServer = [DNSServer]::New('CreatedForTest')

$VirtualDNSrecords = @([DNSRecord]::New('vnone', $VirtualDNSServer.GetFQName(), 'vdnsrecord-nonetest', '1.1.1.1', 'A'),
    [DNSRecord]::New('vdefa', $VirtualDNSServer.GetFQName(), 'vdnsrecord-defaulttest', '1.1.1.2', 'A'),
    [DNSRecord]::New('vvirt', $VirtualDNSServer.GetFQName(), 'vdnsrecord-virtualtest', '1.1.1.3', 'A'),
    [DNSRecord]::New('vtena', $VirtualDNSServer.GetFQName(), 'vdnsrecord-tenanttest', '1.1.1.4', 'A'))

$DefaultDNSrecords = @([DNSRecord]::New('vnone', $null, 'defaultrecord-nonetest.com', '3.3.3.1', 'A'),
    [DNSRecord]::New('vdefa', $null, 'defaultrecord-defaulttest.com', '3.3.3.2', 'A'),
    [DNSRecord]::New('vvirt', $null, 'defaultrecord-virtualtest.com', '3.3.3.3', 'A'),
    [DNSRecord]::New('vtena', $null, 'defaultrecord-tenanttest.com', '3.3.3.4', 'A'))

# This function is used to generate command that will be passed to docker exec.
# $Hostname will be substituted.
# Be carreful while changing it. It has to work after replacing each newline with ';' .
# For instance, don't use if/else because VSCode auto-formatter will move else to newline,
# and "if{...};else{}" is not proper PS code.
function Resolve-DNSLocally {
    $resolved = (Resolve-DnsName -Name $Hostname -Type A -ErrorAction SilentlyContinue)

    if (0 -eq $error.Count) {
        Write-Host 'found'
        $resolved[0].IPAddress
        return
    }

    Write-Host 'error'
    $error[0].CategoryInfo.Category
}
$ResolveDNSLocallyCommand = (${function:Resolve-DNSLocally} -replace "`n|`r", ";")

function Start-Container {
    Param (
        [Parameter(Mandatory = $true)] [Testbed] $Testbed,
        [Parameter(Mandatory = $true)] [string] $ContainerID,
        [Parameter(Mandatory = $false)] [string] $ContainerImage = $null,
        [Parameter(Mandatory = $true)] [string] $NetworkName,
        [Parameter(Mandatory = $false)] [string] $IP
    )

    Write-Log "Creating container: $ContainerID"
    New-Container `
        -Testbed $Testbed `
        -NetworkName $NetworkName `
        -Name $ContainerID `
        -Image $ContainerImage `
        -IP $IP

    Write-Log 'Getting container NetAdapter Information'
    $ContainerNetInfo = Get-RemoteContainerNetAdapterInformation `
        -Session $Testbed.GetSession() -ContainerID $ContainerID
    $IP = $ContainerNetInfo.IPAddress
    Write-Log "IP of $ContainerID : $IP"

    return $IP
}

function Start-DNSServerOnTestBed {
    Param (
        [Parameter(Mandatory = $true)] [Testbed] $Testbed
    )
    Write-Log 'Starting Test DNS Server on test bed...'
    $DefaultDNSServerDir = 'C:\DNS_Server'
    Invoke-Command -Session $Testbed.GetSession() -ScriptBlock {
        New-Item -ItemType Directory -Force $Using:DefaultDNSServerDir | Out-Null
        New-Item "$($Using:DefaultDNSServerDir + '\zones')" -Type File -Force
        foreach ($Record in $Using:DefaultDNSrecords) {
            Add-Content -Path "$($Using:DefaultDNSServerDir + '\zones')" -Value "$($Record.HostName)    $($Record.Type)    $($Record.Data)"
        }
    }

    Copy-Item -ToSession $Testbed.GetSession() -Path ($DockerfilesPath + 'python-dns\dnserver.py') -Destination $DefaultDNSServerDir
    Invoke-Command -Session $Testbed.GetSession() -ScriptBlock {
        $env:ZONE_FILE = "$($Using:DefaultDNSServerDir + '\zones')"
        Start-Process -FilePath 'python' -ArgumentList "$($Using:DefaultDNSServerDir + '\dnserver.py')"
    }
}

function Set-DNSServerAddressOnTestBed {
    Param (
        [Parameter(Mandatory = $true)] [Testbed] $Client,
        [Parameter(Mandatory = $true)] [Testbed] $Server
    )
    $DefaultDNSServerAddress = Invoke-Command -Session $Server.GetSession() -ScriptBlock {
        Get-NetIPAddress -InterfaceAlias $Using:Server.MgmtAdapterName | Where-Object { 2 -eq $_.AddressFamily } | Select-Object -ExpandProperty IPAddress
    }
    Write-Log "Setting default DNS Server on test bed for: $DefaultDNSServerAddress..."
    $OldDNSs = Invoke-Command -Session $Client.GetSession() -ScriptBlock {
        Get-DnsClientServerAddress -InterfaceAlias $Using:Client.MgmtAdapterName | Where-Object {2 -eq $_.AddressFamily} | Select-Object -ExpandProperty ServerAddresses
    }
    Invoke-Command -Session $Client.GetSession() -ScriptBlock {
        Set-DnsClientServerAddress -InterfaceAlias $Using:Client.MgmtAdapterName -ServerAddresses $Using:DefaultDNSServerAddress
    }

    return $OldDNSs
}

function Restore-DNSServerOnTestBed {
    Param (
        [Parameter(Mandatory = $true)] [Testbed] $Client,
        [Parameter(Mandatory = $true)] [String] $InterfaceAlias,
        [Parameter(Mandatory = $true)] [String] $OldDns
    )
    Write-Log 'Restoring old DNS servers on test bed...'
    Invoke-Command -Session $Client.GetSession() -ScriptBlock {
        Set-DnsClientServerAddress -InterfaceAlias $Using:InterfaceAlias -ServerAddresses $Using:OldDns
    }
}

function Resolve-DNS {
    Param (
        [Parameter(Mandatory = $true)] [Testbed] $Testbed,
        [Parameter(Mandatory = $true)] [String] $ContainerName,
        [Parameter(Mandatory = $true)] [String] $Hostname
    )

    $Command = $ResolveDNSLocallyCommand -replace '\$Hostname', ('"' + $Hostname + '"')

    $Result = (Invoke-Command -Session $Testbed.GetSession() -ScriptBlock {
            docker exec $Using:ContainerName powershell $Using:Command
        }).Split([Environment]::NewLine)

    Write-Log "Resolving effect: $($Result[0]) - $($Result[1])"

    if ('error' -eq $Result[0]) {
        return @{'error' = $Result[1]; 'result' = $null}
    }

    return @{'error' = $null; 'result' = $Result[1]}
}

function ResolveCorrectly {
    Param (
        [Parameter(Mandatory = $true)] [String] $Hostname,
        [Parameter(Mandatory = $false)] [String] $IP = 'Any'
    )

    Write-Log "Trying to resolve host '$Hostname', expecting ip '$IP'"

    $result = Resolve-DNS -Testbed $Testenv.Testbeds[0] `
        -ContainerName $ContainersIDs[0] -Hostname $Hostname

    if ((-not $result.error)) {
        if (('Any' -eq $IP) -or ($result.result -eq $IP)) {
            return $true
        }
    }
    return $false
}

function ResolveWithError {
    Param (
        [Parameter(Mandatory = $true)] [String] $Hostname,
        [Parameter(Mandatory = $true)] [String] $ErrorType
    )

    Write-Log "Trying to resolve host '$Hostname', expecting error '$ErrorType'"

    $result = Resolve-DNS -Testbed $Testenv.Testbeds[0] `
        -ContainerName $ContainersIDs[0] -Hostname $Hostname
    return (($result.error -eq $ErrorType) -and (-not $result.result))
}

Test-WithRetries 3 {
    # TODO This test should be eventually marked as "Smoke".
    Describe 'DNS tests' -Tags EnvSafe {
        BeforeAll {
            $Testenv = [Testenv]::New()
            $Testenv.Initialize($TestenvConfFile, $LogDir, $ContrailProject, $PrepareEnv)

            $BeforeAllStack = $Testenv.NewCleanupStack()

            Install-DNSTestDependencies -Testbeds $Testenv.Testbeds
            Start-DNSServerOnTestBed -Testbed $Testenv.Testbeds[1]
            $OldDNSs = Set-DNSServerAddressOnTestBed `
                -Client $Testenv.Testbeds[0] `
                -Server $Testenv.Testbeds[1]
            $BeforeAllStack.Push(${function:Restore-DNSServerOnTestBed}, @($Testenv.Testbeds[0], $Testenv.Testbeds[0].MgmtAdapterName, $OldDNSs))

            Write-Log 'Creating Virtual DNS Server in Contrail...'
            $Testenv.ContrailRepo.AddOrReplace($VirtualDnsServer)
            $BeforeAllStack.Push($VirtualDnsServer)

            foreach ($DnsRecord in $VirtualDnsRecords) {
                $Testenv.ContrailRepo.Add($DnsRecord)
                $BeforeAllStack.Push($DnsRecord)
            }

            Write-Log "Creating virtual network: $($VirtualNetwork.Name)"
            $Testenv.ContrailRepo.AddOrReplace($VirtualNetwork) | Out-Null
            $BeforeAllStack.Push($VirtualNetwork)

            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSUseDeclaredVarsMoreThanAssignments', '',
                Justification = "Analyzer doesn't understand relation of Pester blocks"
            )]
            $BeforeEachStack = $Testenv.NewCleanupStack()
        }

        AfterAll {
            $Testenv.Cleanup()
        }

        function BeforeEachContext {
            Param (
                [Parameter(Mandatory = $true)] [IPAMDNSSettings] $DNSSettings
            )

            $IPAM = [IPAM]::New()
            $IPAM.DNSSettings = $DNSSettings
            $Testenv.ContrailRepo.Set($IPAM)

            foreach ($Testbed in $Testenv.Testbeds) {
                Initialize-DockerNetworks `
                    -Session $Testbed.GetSession() `
                    -Networks @($VirtualNetwork) `
                    -TenantName $ContrailProject
                $BeforeEachStack.Push(${function:Remove-AllUnusedDockerNetworks}, @($Testbed))
            }

            Start-Container -Testbed $Testenv.Testbeds[0] `
                -ContainerID $ContainersIDs[0] `
                -NetworkName $VirtualNetwork.Name
            $BeforeEachStack.Push(${function:Remove-AllContainers}, @(, $Testenv.Testbeds))

            $ContainersLogs = @((New-ContainerLogSource -Testbeds $Testenv.Testbeds[0] -ContainerNames $ContainersIds[0]),
                (New-ContainerLogSource -Testbeds $Testenv.Testbeds[1] -ContainerNames $ContainersIds[1]))
            $BeforeEachStack.Push(${function:Merge-Logs}, @(, $ContainersLogs))
        }

        function AfterEachContext {
            $BeforeEachStack.RunCleanup($Testenv.ContrailRepo)
        }

        AfterEach {
            Merge-Logs -LogSources $Testenv.LogSources
        }

        Context 'DNS mode none' {
            BeforeAll { BeforeEachContext -DNSSetting ([NoneDNSSettings]::New()) }

            AfterAll { AfterEachContext }

            It 'timeouts resolving juniper.net' {
                ResolveWithError `
                    -Hostname 'Juniper.net' `
                    -ErrorType 'OperationTimeout' `
                    | Should -BeTrue
            }
        }

        # TODO Repair and uncomment
        #      When Agent is started before DNS server on host, it reservers port 53.
        #      This results in default DNS mode not working, because server is not listening.
        # Context 'DNS mode default (may fail if run on working env)' {
        #     BeforeAll { BeforeEachContext -DNSSetting ([DefaultDNSSettings]::New()) }

        #     AfterAll { AfterEachContext }

        #     It "doesn't resolve juniper.net" {
        #         ResolveWithError `
        #             -Hostname 'Juniper.net' `
        #             -ErrorType 'ResourceUnavailable' `
        #             | Should -BeTrue
        #     }

        #     It "doesn't resolve virtual DNS" {
        #         ResolveWithError `
        #             -Hostname 'vdnsrecord-defaulttest.default-domain' `
        #             -ErrorType 'ResourceUnavailable' `
        #             | Should -BeTrue
        #     }

        #     It 'resolves default DNS server' {
        #         ResolveCorrectly `
        #             -Hostname 'defaultrecord-defaulttest.com' `
        #             -IP '3.3.3.2' `
        #             | Should -BeTrue
        #     }
        # }

        Context 'DNS mode virtual' {
            BeforeAll { BeforeEachContext -DNSSetting ([VirtualDNSSettings]::New($VirtualDNSServer.GetFQName())) }

            AfterAll { AfterEachContext }

            It 'resolves juniper.net' {
                ResolveCorrectly `
                    -Hostname 'juniper.net' `
                    | Should -BeTrue
            }

            It 'resolves virtual DNS' {
                ResolveCorrectly `
                    -Hostname 'vdnsrecord-virtualtest.default-domain' `
                    -IP '1.1.1.3' `
                    | Should -BeTrue
            }

            It "doesn't resolve default DNS server" {
                ResolveWithError `
                    -Hostname 'defaultrecord-virtualtest.com' `
                    -ErrorType 'ResourceUnavailable' `
                    | Should -BeTrue
            }
        }

        Context 'DNS mode tenant' {
            BeforeAll {
                BeforeEachContext -DNSSetting ([TenantDNSSettings]::New(@($TenantDNSServerAddress)))

                Start-Container `
                    -Testbed $Testenv.Testbeds[1] `
                    -ContainerID $ContainersIDs[1] `
                    -ContainerImage 'python-dns' `
                    -NetworkName $VirtualNetwork.Name `
                    -IP $TenantDNSServerAddress
            }

            AfterAll { AfterEachContext }

            It "doesn't resolve juniper.net" {
                ResolveWithError `
                    -Hostname 'juniper.net' `
                    -ErrorType 'ResourceUnavailable' `
                    | Should -BeTrue
            }

            It "doesn't resolve virtual DNS" {
                ResolveWithError `
                    -Hostname 'vdnsrecord-tenanttest.default-domain' `
                    -ErrorType 'ResourceUnavailable' `
                    | Should -BeTrue
            }

            It "doesn't resolve default DNS server" {
                ResolveWithError `
                    -Hostname 'defaultrecord-tenanttest.com' `
                    -ErrorType 'ResourceUnavailable' `
                    | Should -BeTrue
            }

            It 'resolves tenant DNS' {
                ResolveCorrectly `
                    -Hostname 'tenantrecord-tenanttest.com' `
                    -IP '2.2.2.4' `
                    | Should -BeTrue
            }
        }
    }
}
