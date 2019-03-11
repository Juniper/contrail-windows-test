Param (
    [Parameter(Mandatory=$false)] [string] $TestenvConfFile,
    [Parameter(ValueFromRemainingArguments=$true)] $UnusedParams
)

. $PSScriptRoot/Init.ps1
. $PSScriptRoot/../Testenv/Testbed.ps1

. $PSScriptRoot/Invoke-NativeCommand.ps1

# The following tests use the INC wrapper for Invoke-NativeCommand,
# so the functional tests suite can be easily run both remotely and locally.
function Invoke-FunctionalTests {
    It "can accept the scriptblock also as an explicit parameter" {
        INC -CaptureOutput -ScriptBlock { whoami.exe }
    }

    It "throws on failed command" {
        { INC { whoami.exe /invalid_parameter } } | Should Throw
    }

    It "throws on nonexisting command" {
        { INC { asdfkljasdsdf.exe } } | Should Throw
    }

    It "captures the exitcode of a successful command" {
        $Result = INC -AllowNonZero { whoami.exe }
        $Result.ExitCode | Should Be 0
    }

    It "captures the exitcode a failed command" {
        (INC -AllowNonZero { whoami.exe /invalid }).ExitCode | Should Not Be 0
    }

    It "can capture the output of a command" {
        (INC -CaptureOutput { whoami.exe }).Output | Should BeLike '*\*'
        Get-WriteHostOutput | Should BeNullOrEmpty
    }

    It "prints the error output of a failed command" {
        { INC -CaptureOutput { whoami.exe /invalid } } | Should Throw
        Get-WriteHostOutput | Should Not BeNullOrEmpty
    }

    It "can capture multiline output" {
        (INC -CaptureOutput { whoami.exe /? }).Output.Count | Should BeGreaterThan 1
    }

    It "does not capture the output by default" {
        INC { whoami.exe } | Should BeNullOrEmpty
    }

    It "allows the successful command to print on stderr" {
        INC { Write-Error "simulated stderr"; whoami.exe }
        (Get-WriteHostOutput)[0] | Should BeLike '*stderr*'
    }

    It "doesn't leave a trace of LastExitCode" {
        INC -ScriptBlock { whoami.exe }
        $LastExitCode | Should BeNullOrEmpty
    }
}

Describe "Invoke-NativeCommand - Unit tests" -Tags CISelfcheck, Unit {
    BeforeAll {
        Mock Write-Host {
            param([Parameter(ValueFromPipeline = $true)] $Object)
            $Script:WriteHostOutput += $Object
        }

        function Get-WriteHostOutput {
            $Script:WriteHostOutput
        }
    }

    BeforeEach {
        $Script:WriteHostOutput = @()
    }

    Context "Examples" {
        It "works on a simple case" {
            Invoke-NativeCommand { whoami.exe }
            Get-WriteHostOutput | Should BeLike '*\*'
        }

        It "can capture the exitcode" {
            $Command = Invoke-NativeCommand -AllowNonZero { whoami.exe /invalid_parameter }
            $Command.ExitCode | Should BeGreaterThan 0
        }

        It "can capture the output" {
            $Command = Invoke-NativeCommand -CaptureOutput { whoami.exe }
            $Command.Output | Should BeLike '*\*'
        }
    }

    Context "Local machine" {
        function INC {
            Invoke-NativeCommand @args
        }

        It "can use variables in scriptblock" {
            # This test also makes sure that we're not running it on remote machine,
            # as the variable won't work there
            $Command = "whoami.exe"
            (INC -CaptureOutput -AllowNonZero { & $Command }).ExitCode | Should Be 0
        }

        $ErrorActions = @("Stop", "Continue") | Foreach-Object { @{ErrorAction = $_ } }
        It "preserves the <ErrorAction> ErrorActionPreference" -TestCases $ErrorActions {
            Param($ErrorAction)

            $ErrorActionPreference = $ErrorAction
            INC -CaptureOutput { whoami.exe } | Out-Null
            $ErrorActionPreference | Should Be $ErrorAction
        }

        Invoke-FunctionalTests
    }
}

Describe "Invoke-NativeCommand - System tests" -Tags CISelfcheck, Systest {
    BeforeAll {
        $Testbed = ([Testbed]::LoadFromFile($TestenvConfFile))[0]
        $Sessions = New-RemoteSessions -VMs $Testbed
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments", "Session",
            Justification="Analyzer doesn't understand relation of Pester blocks"
        )]
        $Session = $Sessions[0]

        Mock Write-Host {
            param([Parameter(ValueFromPipeline = $true)] $Object)
            $Script:WriteHostOutput += $Object
        }

        function Get-WriteHostOutput {
            $Script:WriteHostOutput
        }
    }

    AfterAll {
        if (-not (Get-Variable Sessions -ErrorAction SilentlyContinue)) { return }
        Remove-PSSession $Sessions
    }

    BeforeEach {
        $Script:WriteHostOutput = @()
    }

    Context "Examples" {
        It "can be used on remote session" {
            Invoke-NativeCommand -Session $Session { whoami.exe }
            Get-WriteHostOutput | Should BeLike "*\$( $Testbed.Username )"
        }
    }

    Context "Remote machine" {
        function INC {
            Invoke-NativeCommand -Session $Session @args
        }

        It "can use variables in scriptblock" {
            # This test also makes sure that the mock's working and
            # we're not running it on local machine, as Using works only on remote.
            $Command = "whoami.exe"
            (INC -CaptureOutput -AllowNonZero { & $Using:Command }).ExitCode | Should Be 0
        }

        It "preserves the ErrorActionPreference" {
            $OldEA = Invoke-Command { $ErrorActionPreference }
            INC -CaptureOutput { whoami.exe } | Out-Null
            Invoke-Command { $ErrorActionPreference } | Should Be $OldEA
        }

        Invoke-FunctionalTests
    }
}
