. $PSScriptRoot\..\Utils\PowershellTools\Init.ps1
. $PSScriptRoot\..\Utils\PowershellTools\Invoke-CommandInLocation.ps1

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"

Describe "PesterLogger" -Tags CISelfcheck, Unit {
    Context "Initialize-PesterLogger" {
        It "registers a new global Write-LogImpl function" {
            Initialize-PesterLogger -OutDir "TestDrive:\"
            Get-Item function:Write-LogImpl -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "unregisters previous Write-LogImpl function and registers a new one" {
            function OldImpl {}
            Mock OldImpl {}
            New-Item function:Write-LogImpl -Value OldImpl
            Write-Log "test"

            Initialize-PesterLogger -OutDir "TestDrive:\"
            Get-Item function:Write-LogImpl -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty

            Write-Log "test2"
            Assert-MockCalled OldImpl -Exactly -Times 1
        }

        It "creates output directory if it doesn't exist" {
            Initialize-PesterLogger -OutDir "TestDrive:\some_dir"
            "TestDrive:\some_dir" | Should -Exist
        }
    }

    Context "Write-Log" {
        It "changing location doesn't change the output directory" {
            Invoke-CommandInLocation TestDrive:\ {
                Initialize-PesterLogger -OutDir "."

                New-Item -ItemType directory TestDrive:\abcd

                Invoke-CommandInLocation TestDrive:\abcd {
                    Write-Log "msg"
                }
            }
            "TestDrive:\PesterLogger.Write-Log.changing location doesn't change the output directory.txt" `
                | Should -Exist
        }

        It "writes correct messages" {
            Initialize-PesterLogger -OutDir "TestDrive:\"
            Write-Log "msg1"
            Write-Log "msg2"
            Get-Content "TestDrive:\PesterLogger.Write-Log.writes correct messages.txt" |
                ConvertTo-LogItem | Foreach-Object Message | Should -Be ("msg1", "msg2")
        }

        It "allows for null messages" {
            Initialize-PesterLogger -OutDir "TestDrive:\"
            Write-Log $null
            Get-Content "TestDrive:\PesterLogger.Write-Log.allows for null messages.txt" |
                ConvertTo-LogItem | Foreach-Object Message | Should -Be ("<EMPTY>")
        }

        It "can write non-strings" {
            Initialize-PesterLogger -OutDir "TestDrive:\"
            Write-Log $true
            Get-Content "TestDrive:\PesterLogger.Write-Log.can write non-strings.txt" |
                ConvertTo-LogItem | Foreach-Object Message | Should -Be "True"
        }

        It "can write arrays" {
            Initialize-PesterLogger -OutDir "TestDrive:\"
            Write-Log ("foo", "bar")
            Get-Content "TestDrive:\PesterLogger.Write-Log.can write arrays.txt" |
                ConvertTo-LogItem | Foreach-Object Message | Should -Be ("foo", "bar")
        }

        It "writes to correct file" {
            Initialize-PesterLogger -OutDir "TestDrive:\"
            Write-Log "msg"
            Test-Path "TestDrive:\PesterLogger.Write-Log.writes to correct file.txt" | Should -Be $true
        }

        It "errors if test name contains : " { # shelly: allow invalid-testname-characters
            Initialize-PesterLogger -OutDir "TestDrive:\"
            { Write-Log "msg1" } | Should -Throw
        }

        It "errors if test name contains / " { # shelly: allow invalid-testname-characters
            Initialize-PesterLogger -OutDir "TestDrive:\"
            { Write-Log "msg1" } | Should -Throw
        }

        Context "Timestamps" {
            $RealGetDate = Get-Command Get-Date -CommandType Cmdlet
            Mock Get-Date {
                & $RealGetDate `
                    -Year 2018 `
                    -Month 6 `
                    -Day 8 `
                    -Hour 14 `
                    -Minute 46 `
                    -Second 44 `
                    -Millisecond 42 `
                    @Args
            }

            It "are present in logs" {
                Initialize-PesterLogger -OutDir "TestDrive:\"
                Write-Log "foo"
                Get-Content "TestDrive:\PesterLogger.Write-Log.Timestamps.are present in logs.txt" |
                    ConvertTo-LogItem | Foreach-Object Timestamp | Should -Be "2018-06-08 14:46:44.042000"
            }

            It "can be disabled" {
                Initialize-PesterLogger -OutDir "TestDrive:\"
                Write-Log -NoTimestamps "foo"
                Get-Content "TestDrive:\PesterLogger.Write-Log.Timestamps.can be disabled.txt" |
                    ConvertTo-LogItem | Foreach-Object Timestamp | Should -BeNullOrEmpty
            }
        }

        Context "Tags" {
            It "default to test-runner" {
                Initialize-PesterLogger -OutDir "TestDrive:\"
                Write-Log "foo"
                Get-Content "TestDrive:\PesterLogger.Write-Log.Tags.default to test-runner.txt" |
                    ConvertTo-LogItem | Foreach-Object Tag | Should -Be "test-runner"
            }

            It "can be set" {
                Initialize-PesterLogger -OutDir "TestDrive:\"
                Write-Log -Tag "testbed" "foo"
                Get-Content "TestDrive:\PesterLogger.Write-Log.Tags.can be set.txt" |
                    ConvertTo-LogItem | Foreach-Object Tag | Should -Be "testbed"
            }
        }

        Context "Formatting" {
            It "looks as expected with timestamps" {
                Initialize-PesterLogger -OutDir "TestDrive:\"
                Write-Log "foo"
                Get-Content "TestDrive:\PesterLogger.Write-Log.Formatting.looks as expected with timestamps.txt" |
                    Should -BeLike "????-??-?? ??:??:??.?????? | test-runner | foo"
            }

            It "looks as expected without timestamps" {
                Initialize-PesterLogger -OutDir "TestDrive:\"
                Write-Log -NoTimestamps "foo"
                Get-Content "TestDrive:\PesterLogger.Write-Log.Formatting.looks as expected without timestamps.txt" |
                    Should -BeLike "                           | test-runner | foo"
            }
        }
    }

    Context "Initializing in BeforeEach" {
        It "registers Write-Log correctly" {
            Write-Log "hi"
            Get-Content "TestDrive:\PesterLogger.Initializing in BeforeEach.registers Write-Log correctly.txt" `
                | ConvertTo-LogItem | Foreach-Object Message | Should -Be "hi"
        }
        BeforeEach {
            Initialize-PesterLogger -OutDir "TestDrive:\"
        }
    }

    AfterEach {
        if (Get-Item function:Write-LogImpl -ErrorAction SilentlyContinue) {
            Remove-Item function:Write-LogImpl
        }
    }
}
