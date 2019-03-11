Param (
    [Parameter(Mandatory=$false)] [string] $TestenvConfFile,
    [Parameter(ValueFromRemainingArguments=$true)] $UnusedParams
)

. $PSScriptRoot\..\..\Utils\PowershellTools\Init.ps1

. $PSScriptRoot\Impl.ps1

Describe "Get-RemoteContainerNetAdapterInformation - Unit tests" -Tags CISelfcheck, Unit {
    Context "Valid structure" {
        BeforeAll {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                "PSUseDeclaredVarsMoreThanAssignments", "",
                Justification="Analyzer doesn't understand relation of Pester blocks"
            )]
            $RawAdapterInfo = @{
                ifIndex = 1
                ifName = 'testifname'
                Name = 'vEthernet (testnet123)'
                MacAddress = 'A1-B2-C3-D4-E5-F6'
                IPAddress = '1.2.3.4'
                MtuSize = '1500'
            }
        }

        It "should not throw when validating IPAddress" {
            {
                Assert-IsIpAddressInRawNetAdapterInfoValid -RawAdapterInfo $RawAdapterInfo
            } | Should -Not -Throw
        }

        It "is properly converted to ContainerNetAdapterInformation" {
            $AdapterInfo = ConvertFrom-RawNetAdapterInformation -RawAdapterInfo $RawAdapterInfo

            $AdapterInfo.AdapterShortName | Should -BeExactly 'testnet123'
            $AdapterInfo.AdapterFullName | Should -BeExactly 'vEthernet (testnet123)'
            $AdapterInfo.IPAddress | Should -BeExactly '1.2.3.4'
            $AdapterInfo.IfIndex | Should -BeExactly 1
            $AdapterInfo.IfName | Should -BeExactly 'testifname'
            $AdapterInfo.MACAddress | Should -BeExactly 'a1:b2:c3:d4:e5:f6'
            $AdapterInfo.MACAddressWindows | Should -BeExactly 'a1-b2-c3-d4-e5-f6'
            $AdapterInfo.MtuSize | Should -BeExactly '1500'
        }
    }

    Context "Invalid IPAddress" {
        BeforeAll {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                "PSUseDeclaredVarsMoreThanAssignments", "",
                Justification="Analyzer doesn't understand relation of Pester blocks"
            )]
            $RawAdapterInfo = @{
                IPAddress = @{
                    value = @(
                        '1.2.3.4',
                        '5.6.7.8'
                    )
                    Count = 2
                }
            }
        }

        It "should throw when validating IPAddress" {
            {
                Assert-IsIpAddressInRawNetAdapterInfoValid -RawAdapterInfo $RawAdapterInfo
            } | Should -Throw
        }
    }
}
