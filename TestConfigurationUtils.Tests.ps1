. $PSScriptRoot\Utils\PowershellTools\Init.ps1
. $PSScriptRoot\TestConfigurationUtils.ps1

Describe "Select-ValidNetIPInterface unit tests" -Tags CISelfcheck, Unit {
    Context "Single valid/invalid Get-NetIPAddress output" {
        It "Both AddressFamily and SuffixOrigin match" {
            $ValidGetNetIPAddress = @{ AddressFamily = "IPv4"; SuffixOrigin = "Dhcp" }
            $ValidGetNetIPAddress | Select-ValidNetIPInterface | Should Be $ValidGetNetIPAddress

            $ValidGetNetIPAddress = @{ AddressFamily = "IPv4"; SuffixOrigin = "Manual" }
            $ValidGetNetIPAddress | Select-ValidNetIPInterface | Should Be $ValidGetNetIPAddress
        }
        It "One or all attributes don't match" {
            $InvalidCases = @(
                @{ AddressFamily = "IPv4"; SuffixOrigin = "WellKnown" },
                @{ AddressFamily = "IPv6"; SuffixOrigin = "Manual" },
                @{ AddressFamily = "IPv6"; SuffixOrigin = "Link" }
            )

            foreach($InvalidCase in $InvalidCases) {
                $InvalidCase | Select-ValidNetIPInterface | Should BeNullOrEmpty
            }
        }
    }
    Context "Get-NetIPAddress returns an array" {
        It "Pass valid/invalid object combinations into pipeline" {
            $InvalidGetNetIPAddress = @{
                AddressFamily = "IPv4"
                SuffixOrigin = "WellKnown"
            }
            $ValidGetNetIPAddress = @{
                AddressFamily = "IPv4"
                SuffixOrigin = "Dhcp"
            }

            @( $InvalidGetNetIPAddress, $ValidGetNetIPAddress ) | `
            Select-ValidNetIPInterface | Should Be $ValidGetNetIPAddress

            @( $ValidGetNetIPAddress, $InvalidGetNetIPAddress ) | `
            Select-ValidNetIPInterface | Should Be $ValidGetNetIPAddress

            @( $InvalidGetNetIPAddress, $InvalidGetNetIPAddress ) | `
            Select-ValidNetIPInterface | Should BeNullOrEmpty
        }
    }
}
