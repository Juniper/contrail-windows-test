. $PSScriptRoot\..\..\Utils\PowershellTools\Invoke-NativeCommand.ps1

function Get-DockerfilesPath {
    return 'C:\DockerFiles'
}

function Get-DNSDockerName {
    return 'python-dns'
}
function Sync-MicrosoftDockerImagesOnTestbeds {
    Param (
        [Parameter(Mandatory = $true)] [Testbed[]] $Testbeds
    )

    Write-Log 'Downloading Docker images'
    $StartedJobs = @()
    ForEach ($Testbed in $Testbeds) {
        $JobName = "$($Testbed.GetSession().ComputerName)-pulldockerms"
        switch ($Testbed.WinVersion) {
            'v2016' {
                $Images = @('microsoft/windowsservercore:ltsc2016')
            }
            'v2019' {
                $Images = @('mcr.microsoft.com/windows/servercore:1809')
            }
        }
        Invoke-Command -Session $Testbed.GetSession() -JobName $JobName -AsJob {
            foreach($Image in $Using:Images) {
                docker pull $Image
            }
        } | Out-Null
        $StartedJobs += $JobName
    }
    ForEach ($StartedJob in $StartedJobs) {
        Wait-Job -Name $StartedJob | Out-Null
        $Result = Receive-Job -Name $StartedJob
        Write-Log "Job '$StartedJob' result: $Result"
    }
}

function Install-DNSTestDependencies {
    Param (
        [Parameter(Mandatory = $true)] [Testbed[]] $Testbeds
    )
    $DNSDockerfilePath = Join-Path (Get-DockerfilesPath) (Get-DNSDockerName)
    foreach ($Testbed in $Testbeds) {
        Write-Log 'Configuring dependencies for DNS tests'
        $Result = Invoke-NativeCommand -Session $Testbed.GetSession() -AllowNonZero -CaptureOutput {
            New-Item -ItemType directory -Path $Using:DNSDockerfilePath -Force
            pip  download dnslib==0.9.7 --dest $Using:DNSDockerfilePath
            pip  install dnslib==0.9.7
            pip  install pathlib==1.0.1
        }
        Write-Log $Result.Output
        if (0 -ne $Result.ExitCode) {
            Write-Warning 'Installing DNS test dependecies failed'
        }
        else {
            Write-Log 'DNS test dependencies installed successfully'
        }
    }
}
