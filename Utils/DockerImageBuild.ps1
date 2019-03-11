. $PSScriptRoot\..\Utils\PowershellTools\Aliases.ps1
. $PSScriptRoot\..\Utils\PowershellTools\Invoke-NativeCommand.ps1
. $PSScriptRoot\..\Utils\PowershellTools\Invoke-UntilSucceeds.ps1
. $PSScriptRoot\..\PesterLogger\PesterLogger.ps1

$DockerfilesPath = "$PSScriptRoot\..\DockerFiles\"

function Test-Dockerfile {
    Param ([Parameter(Mandatory = $true)] [string] $DockerImageName)

    Test-Path (Join-Path $DockerfilesPath $DockerImageName)
}

function Initialize-DockerImage  {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $true)] [string] $DockerImageName
    )

    $DockerfilePath = $DockerfilesPath + $DockerImageName
    $TestbedDockerfilesDir = "C:\DockerFiles\"
    Invoke-Command -Session $Session -ScriptBlock {
        New-Item -ItemType Directory -Force $Using:TestbedDockerfilesDir | Out-Null
    }

    Write-Log "Copying directory with Dockerfile"
    Copy-Item -ToSession $Session -Path $DockerfilePath -Destination $TestbedDockerfilesDir -Recurse -Force

    Write-Log "Building Docker image"
    $TestbedDockerfilePath = $TestbedDockerfilesDir + $DockerImageName

    # This retry loop is a workaround for a "container <hash> encountered an error during Start:
    # failure in a Windows system call: This operation returned because the timeout period expired. (0x5b4)".
    # This is probably caused by slow disks or other windows error. See:
    # https://github.com/MicrosoftDocs/Virtualization-Documentation/issues/575
    # https://github.com/moby/moby/issues/27588
    {
        $Command = Invoke-NativeCommand -Session $Session -CaptureOutput -AllowNonZero -ScriptBlock {
            docker build --network none --tag $Using:DockerImageName $Using:TestbedDockerfilePath
        }

        if (0 -eq $Command.ExitCode) {
            return $true
        }

        Write-Log $Command.Output

        if ($Command.Output -Match ".*container.*encountered an error during Start.*0x5b4.*") {
            throw $Command.Output
        } else {
            throw [HardError]::new("hard error", [InvalidOperationException]::new($Command.Output))
        }
    } | Invoke-UntilSucceeds -Name "docker build" -NumRetries 5
}
