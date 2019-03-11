. $PSScriptRoot\Init.ps1
. $PSScriptRoot/Invoke-CommandInLocation.ps1

Describe "Invoke-CommandInLocation" -Tags CISelfcheck, Unit {
    BeforeAll {
        New-Item -Type Directory TestDrive:\foo\bar
    }

    AfterAll {
        Remove-Item -Recurse TestDrive:\foo
    }

    BeforeEach {
        Push-Location (Join-Path $TestDrive foo)
    }

    AfterEach {
        Pop-Location
    }

    It "changes the directory" {
        Invoke-CommandInLocation bar {
            (Get-Location).Path | Should Be (Join-Path $TestDrive foo\bar)
        }
    }

    It "restores the directory" {
        Invoke-CommandInLocation bar {}
        (Get-Location).Path | Should Be (Join-Path $TestDrive foo)
    }

    It "restores the directory after an exception" {
        {
            Invoke-CommandInLocation bar {
                throw "Something"
            }
        } | Should Throw
        (Get-Location).Path | Should Be (Join-Path $TestDrive foo)
    }
}
