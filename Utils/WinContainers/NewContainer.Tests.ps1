Param (
    [Parameter(Mandatory=$false)] [string] $TestenvConfFile,
    [Parameter(Mandatory=$false)] [string] $LogDir = "pesterLogs",
    [Parameter(ValueFromRemainingArguments=$true)] $AdditionalParams
)

. $PSScriptRoot\..\Testenv\Testbed.ps1

Describe "New-Container" -Tags CISelfcheck, Systest {
    It "Reports container id when container creation succeeds in first attempt" {
        Invoke-Command -Session $Testbed.GetSession() {
            $DockerThatAlwaysSucceeds = @"
            Write-Output "{0}"
            exit 0
"@ -f $Using:ContainerID
            Set-Content -Path "docker.ps1" -Value $DockerThatAlwaysSucceeds
        }

        {
            $NewContainerID = New-Container `
                -Testbed $Testbed `
                -NetworkName "BestNetwork" `
                -Name "jolly-lumberjack"
            Set-Variable -Name "NewContainerID" -Value $NewContainerID -Scope 1
        } | Should -Not -Throw
        $NewContainerID | Should -Be $ContainerID
    }

    It "Throws exception when container creation fails" {
        Invoke-Command -Session $Testbed.GetSession() {
            $DockerThatAlwaysFails = @"
            Write-Error "It's Docker here: This is very very bad!"
            exit 1
"@
            Set-Content -Path "docker.ps1" -Value $DockerThatAlwaysFails
        }

        {
            New-Container `
                -Testbed $Testbed `
                -NetworkName "NetworkOfFriends" `
                -Name "jolly-lumberjack"
        } | Should -Throw
    }

    It "Reports container id when container creation succeeds in second attempt after failing because of known issue" {
        Invoke-Command -Session $Testbed.GetSession() {
            $TmpFlagFile = "HopeForLuckyTry"
            Remove-Item $TmpFlagFile -ErrorAction Ignore
            $DockerThatSucceedsInSecondAttempt = @'
            if ("run" -eq $args[0]) {{
                $TmpFlagFile = "{1}"
                if (Test-Path $TmpFlagFile) {{
                    Write-Output "{0}"
                    Remove-Item $TmpFlagFile
                    exit 0
                }} else {{
                    Set-Content -Path $TmpFlagFile -Value "New hope"
                    Write-Output "{0}"
                    Write-Error "It's Docker here: CreateContainer: failure in a Windows system call. Try again. Good luck!"
                    exit 1
                }}
            }} else {{
                Write-Output "{0}"
                exit 0
            }}
'@ -f $Using:ContainerID,$TmpFlagFile
            Set-Content -Path "docker.ps1" -Value $DockerThatSucceedsInSecondAttempt
        }

        {
            $NewContainerID = New-Container `
                -Testbed $Testbed `
                -NetworkName "SoftwareDefinedNetwork" `
                -Name "jolly-lumberjack"
            Set-Variable -Name "NewContainerID" -Value $NewContainerID -Scope 1
        } | Should -Not -Throw
        $NewContainerID | Should -Be $ContainerID
    }

    It "Throws exception when container creation fails in first attempt and reports unknown issue" {
        Invoke-Command -Session $Testbed.GetSession() {
            $TmpFlagFile = "HopeForLuckyTry"
            Remove-Item $TmpFlagFile -ErrorAction Ignore
            $DockerThatSucceedsInSecondAttempt = @'
            if ("run" -eq $args[0]) {{
                $TmpFlagFile = "{1}"
                if (Test-Path $TmpFlagFile) {{
                    Write-Output "{0}"
                    Remove-Item $TmpFlagFile
                    exit 0
                }} else {{
                    Set-Content -Path $TmpFlagFile -Value "There's actually no hope."
                    Write-Output "{0}"
                    Write-Error "It's Docker here: unknown error."
                    exit 1
                }}
            }} else {{
                Write-Output "{0}"
                exit 0
            }}
'@ -f $Using:ContainerID,$TmpFlagFile
            Set-Content -Path "docker.ps1" -Value $DockerThatSucceedsInSecondAttempt
        }

        {
            New-Container `
                -Testbed $Testbed `
                -NetworkName "SoftwareDefinedNetwork" `
                -Name "jolly-lumberjack"
        } | Should -Throw
    }

    BeforeAll {
        $Testbeds = [Testbed]::LoadFromFile($TestenvConfFile)
        $Testbed = $Testbeds[0]

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments", "",
            Justification="Lifetime and visibility of variables is a matter beyond capabilities of code checker."
        )]
        $ContainerID = "47f6baf1e42fa83b5ddb6a8dca9103178129ce454689f47ee59140dafc2c9a7c"
        Invoke-Command -Session $Testbed.GetSession() {
            $OldPath = $Env:Path
            $Env:Path = ".;$OldPath"
        }
    }

    AfterAll {
        Invoke-Command -Session $Testbed.GetSession() {
            Remove-Item docker.ps1
        }
    }
}
