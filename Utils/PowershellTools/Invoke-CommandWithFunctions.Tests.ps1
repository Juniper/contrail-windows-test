Param (
    [Parameter(Mandatory=$false)] [string] $TestenvConfFile,
    [Parameter(ValueFromRemainingArguments=$true)] $UnusedParams
)

. $PSScriptRoot/Init.ps1
. $PSScriptRoot/../Testenv/Testbed.ps1

. $PSScriptRoot/Invoke-CommandWithFunctions.ps1

Describe "Invoke-CommandWithFunctions tests" -Tags CISelfcheck, Systest {
    function Test-CWF {
        param(
            [Parameter(Mandatory=$true)] [string[]] $Functions,
            [Parameter(Mandatory=$true)] [ScriptBlock] $ScriptBlock
        )

        Invoke-CommandWithFunctions -Session $Session `
            -Functions $Functions `
            -ScriptBlock $ScriptBlock
    }

    function Test-SimpleFunction {
        param(
            [Parameter(Mandatory=$false)] [string] $SimpleParam = "A simple string to return"
        )

        return $SimpleParam
    }

    Context "Incorrect function usage handling" {
        It "throws on nonexisting function" {
            {
                Test-CWF -Functions "Test-SimpleFunction" -ScriptBlock {
                    Test-ANonExistingFunction # analyzer: allow unknown-functions
                }
            } | Should Throw
        }

        It "throws on invoking with incorrectly passed parameter" {
            { Test-CWF -Functions "Test-SimpleFunction" `
              -ScriptBlock { Test-SimpleFunction -InvalidParam $true } } | Should Throw
        }
    }

    Context "correctly defined simple functions" {
        It "invokes function passed in ScriptBlock" {
            $str = "A simple string"
            Test-CWF -Functions "Test-SimpleFunction" `
                -ScriptBlock { Test-SimpleFunction -SimpleParam $using:str } `
                | Should Be $str
        }

        It "correctly invokes function with parameters defined at remote session" {
            Test-CWF -Functions "Test-SimpleFunction"  `
                -ScriptBlock { $a = "abcd"; Test-SimpleFunction -SimpleParam $a } `
                | Should Be "abcd"
        }
    }

    Context "function invoking another function" {
        function Test-OuterFunction {
            param(
                [Parameter(Mandatory=$true)] [string] $TestString,
                [Switch] $DoAThrow
            )
            [ScriptBlock]$Sb = [ScriptBlock]::Create( $TestString )
            Test-InnerFunction -ScriptBlock $Sb -ArgumentList $TestString -DoAThrow:$DoAThrow
        }

        function Test-InnerFunction {
            param(
                [Parameter(Mandatory=$true)] [ScriptBlock] $ScriptBlock,
                [Parameter(Mandatory=$true)] [Object[]] $ArgumentList,
                [Switch] $DoAThrow
            )

            if ( $DoAThrow ) {
                throw "threw"
            }
            else {
                Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
            }
         }

        $TestFunctions = @("Test-OuterFunction", "Test-InnerFunction")

        It "Inner function calls passed string as scriptblock and outputs result" {
            Test-CWF -Functions $TestFunctions  `
                -ScriptBlock { Test-OuterFunction -TestString "whoami.exe" } `
                | Should Not BeNullOrEmpty
        }

        It "allows to throw exception" {
            { Test-CWF -Functions $TestFunctions  `
              -ScriptBlock { Test-OuterFunction -TestString "" -DoAThrow } } | Should Throw
        }

        It "works with pipelines" {
            function Test-PipelineFunction {
                param([Parameter(ValueFromPipeline=$true)] $notUsed)

                Process { Test-SimpleFunction -SimpleParam $_ }
            }

            $TestPipeline = @("Test-SimpleFunction")
            $TestPipeline += "Test-PipelineFunction";

            Test-CWF -Functions $TestPipeline  `
                -ScriptBlock { 1..5 | Test-PipelineFunction } `
                | Should Be @('1', '2', '3', '4', '5')
        }
    }

    BeforeAll {
        $Testbed = ([Testbed]::LoadFromFile($TestenvConfFile))[0]
        $Sessions = New-RemoteSessions -VMs $Testbed
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments", "Session",
            Justification="Analyzer doesn't understand relation of Pester blocks"
        )]
        $Session = $Sessions[0]
    }
}
