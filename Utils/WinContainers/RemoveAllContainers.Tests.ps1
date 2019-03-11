Param (
    [Parameter(Mandatory = $false)] [string] $TestenvConfFile,
    [Parameter(Mandatory = $false)] [string] $LogDir = "pesterLogs",
    [Parameter(ValueFromRemainingArguments=$true)] $AdditionalParams
)

. $PSScriptRoot\..\Testenv\Configs.ps1
. $PSScriptRoot\..\Testenv\Testbed.ps1

. $PSScriptRoot\Containers.ps1
. $PSScriptRoot\..\..\PesterLogger\PesterLogger.ps1
. $PSScriptRoot\..\..\TestConfigurationUtils.ps1

$NetworkName = "nat"

Describe "Remove-AllContainers" -Tags CISelfcheck, Systest {
    It "Removes single container if exists" {
        New-Container -Testbed $Testbed -NetworkName $NetworkName
        Invoke-Command -Session $Session -ScriptBlock {
            docker ps -aq
        } | Should Not BeNullOrEmpty

        Remove-AllContainers -Session $Session

        Invoke-Command -Session $Session -ScriptBlock {
            docker ps -aq
        } | Should BeNullOrEmpty
    }

    It "Removes mutliple containers if exist" {
        New-Container -Testbed $Testbed -NetworkName $NetworkName
        New-Container -Testbed $Testbed -NetworkName $NetworkName
        New-Container -Testbed $Testbed -NetworkName $NetworkName
        Invoke-Command -Session $Session -ScriptBlock {
            docker ps -aq
        } | Should Not BeNullOrEmpty

        Remove-AllContainers -Session $Session

        Invoke-Command -Session $Session -ScriptBlock {
            docker ps -aq
        } | Should BeNullOrEmpty
    }

    It "Does nothing if list of containers is empty" {
        Remove-AllContainers -Session $Session

        Invoke-Command -Session $Session -ScriptBlock {
            docker ps -aq
        } | Should BeNullOrEmpty
    }

    It "Throws an exception when container removal consistently fails" {
        New-Container -Testbed $Testbed -NetworkName $NetworkName
        Invoke-Command -Session $Session -ScriptBlock {
            docker ps -aq
        } | Should Not BeNullOrEmpty

        Invoke-Command -Session $Session {
            $DockerThatAlwaysFails = @'
            if ("rm" -eq $args[0]) {
                Write-Error "It's Docker here: I will never ever do that!"
                exit 1
            } else {
                docker.exe $args
            }
'@
            Set-Content -Path "docker.ps1" -Value $DockerThatAlwaysFails
        }

        { Remove-AllContainers -Session $Session } | Should -Throw

        Invoke-Command -Session $Session -ScriptBlock {
            docker ps -aq
        } | Should Not BeNullOrEmpty
    }

    It "Removes single container if it exists even if first attempt fails" {
        New-Container -Testbed $Testbed -NetworkName $NetworkName
        Invoke-Command -Session $Session -ScriptBlock {
            docker ps -aq
        } | Should Not BeNullOrEmpty

        $TmpFlagFile = "ShallDockerActuallyWork"
        Invoke-Command -Session $Session {
            $FlakyDocker = @'
            $TmpFlagFile = "{0}"
            if ("rm" -eq $args[0]) {{
                if (Test-Path $TmpFlagFile) {{
                    docker.exe $args
                }} else {{
                    Set-Content -Path $TmpFlagFile -Value "Maybe next time we can make it..."
                    Write-Error "It's Docker here: Not so fast, Cowboy!"
                    exit 1
                }}
            }} else {{
                docker.exe $args
            }}
'@ -f $Using:TmpFlagFile
            Set-Content -Path "docker.ps1" -Value $FlakyDocker
            Remove-Item $Using:TmpFlagFile -ErrorAction Ignore
        }

        Remove-AllContainers -Session $Session

        Invoke-Command -Session $Session -ScriptBlock {
            docker ps -aq
        } | Should BeNullOrEmpty
    }

    AfterEach {
        Invoke-Command -Session $Session {
            Remove-Item docker.ps1 -ErrorAction Ignore
        }
        Clear-TestConfiguration -Testbed $Testbed -SystemConfig $SystemConfig
    }

    BeforeAll {
        $Testbeds = [Testbed]::LoadFromFile($TestenvConfFile)
        $Sessions = New-RemoteSessions -VMs $Testbeds
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments", "",
            Justification="Analyzer doesn't understand relation of Pester blocks"
        )]
        $Session = $Sessions[0]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments", "",
            Justification="Analyzer doesn't understand relation of Pester blocks"
        )]
        $Testbed = $Testbeds[0]

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments", "",
            Justification="Analyzer doesn't understand relation of Pester blocks"
        )]
        $SystemConfig = [SystemConfig]::LoadFromFile($TestenvConfFile)

        Initialize-PesterLogger -OutDir $LogDir

        Invoke-Command -Session $Session {
            $OldPath = $Env:Path
            $Env:Path = ".;$OldPath"
        }
    }

    AfterAll {
        if (-not (Get-Variable Sessions -ErrorAction SilentlyContinue)) { return }
        Remove-PSSession $Sessions
    }
}
