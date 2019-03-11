. $PSScriptRoot\..\Utils\PowershellTools\Init.ps1

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"

function ItBlockOutsideOfDescribe() {
    It "getting Pester scope works in It block outside of Describe" {
        Get-CurrentPesterScope | Should -BeExactly @("Get-CurrentPesterScope", "It blocks in weird places",
            "getting Pester scope works in It block outside of Describe")
    }
}

Describe "Get-CurrentPesterScope" -Tags CISelfcheck, Unit {
    Context "when inside Context block" {
        It "getting Pester scope works" {
            Get-CurrentPesterScope | Should -BeExactly @("Get-CurrentPesterScope",
                "when inside Context block", "getting Pester scope works")
        }

        $Name = "hi"
        It "works when variable called Name is used in test case" {
            [
                Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments",
                "Name",
                Justification="PSAnalyzer doesn't understand relations of Pester's blocks.")
            ]
            $Name = "hi"
            "hi" | Should -Not -BeIn Get-CurrentPesterScope
        }

        function SomeFunc() {
            $Name = "hi"
            function SomeFuncNested() {
                [
                    Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments",
                    "Name",
                    Justification="PSAnalyzer doesn't understand relations of Pester's blocks.")
                ]
                $Name = "hi"
                Get-CurrentPesterScope | Should -BeExactly @("Get-CurrentPesterScope",
                    "when inside Context block", "works with nested functions that override Name")
                Get-CurrentPesterScope
            }
            SomeFuncNested
        }
        It "works with nested functions that override Name" {
            SomeFunc | Should -BeExactly @("Get-CurrentPesterScope",
                "when inside Context block", "works with nested functions that override Name")
        }


    }

    Context "It blocks in weird places" {
        function ItNested() {
            function ItNestedTwice() {
                It "getting Pester scope works in It nested twice" {
                    Get-CurrentPesterScope | Should -BeExactly @("Get-CurrentPesterScope",
                        "It blocks in weird places", "getting Pester scope works in It nested twice")
                }
            }
            It "getting Pester scope works in It nested once" {
                Get-CurrentPesterScope | Should -BeExactly @("Get-CurrentPesterScope",
                    "It blocks in weird places", "getting Pester scope works in It nested once")
            }
            ItNestedTwice
        }
        ItNested
        ItBlockOutsideOfDescribe
    }

    It "getting Pester scope outside of Context works" {
        Get-CurrentPesterScope | Should -BeExactly @("Get-CurrentPesterScope",
            "getting Pester scope outside of Context works")
    }

    It "SANITY CHECK: hack tested only on Pester 4.2.0" {
        $PesterInfo = InModuleScope Pester {
            Get-Module Pester
        }
        if ("4.2.0" -ne $PesterInfo.Version) {
            Set-TestInconclusive
        }
    }
}
