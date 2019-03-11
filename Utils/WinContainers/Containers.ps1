. $PSScriptRoot\..\..\Utils\PowershellTools\Invoke-NativeCommand.ps1

function Remove-AllContainers {
    Param ([Parameter(Mandatory = $true)] [PSSessionT[]] $Sessions)

    Write-Log 'Removing all containers'

    foreach ($Session in $Sessions) {
        $Result = Invoke-NativeCommand -Session $Session -CaptureOutput -AllowNonZero {
            $Containers = docker ps -aq
            $MaxAttempts = 3
            $TimesToGo = $MaxAttempts
            while ( $Containers -and $TimesToGo -gt 0 ) {
                if($Containers) {
                    $Command = "docker rm -f $Containers"
                    Invoke-Expression -Command $Command
                }
                $Containers = docker ps -aq
                $TimesToGo = $TimesToGo - 1
                if ( $Containers -and 0 -eq $TimesToGo ) {
                    $LASTEXITCODE = 1
                }
            }
            Remove-Variable "Containers"
            return $MaxAttempts - $TimesToGo - 1
        }

        $OutputMessages = $Result.Output
        if (0 -ne $Result.ExitCode) {
            throw "Remove-AllContainers - removing containers failed with the following messages: $OutputMessages"
        }
        elseif ($Result.Output[-1] -gt 0) {
            Write-Log "Remove-AllContainers - removing containers was successful, but required more than one attempt: $OutputMessages"
        }
        else {
            Write-Log "Remove-AllContainers - removing containers was successful."
        }
    }
}

function Stop-Container {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $false)] [string] $NameOrId)

    Invoke-Command -Session $Session -ScriptBlock {
        docker kill $Using:NameOrId | Out-Null
    }
}

function Remove-Container {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $false)] [string] $NameOrId)

    Invoke-Command -Session $Session -ScriptBlock {
        docker rm -f $Using:NameOrId | Out-Null
    }
}


function New-Container {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $true)] [string] $NetworkName,
           [Parameter(Mandatory = $false)] [string] $Name,
           [Parameter(Mandatory = $false)] [string] $Image = "microsoft/nanoserver",
           [Parameter(Mandatory = $false)] [string] $IP)

    if (Test-Dockerfile $Image) {
        Initialize-DockerImage -Session $Session -DockerImageName $Image | Out-Null
    }

    $Arguments = "run", "-di"
    if ($Name) { $Arguments += "--name", $Name }
    if ($IP) { $Arguments += "--ip", $IP }
    $Arguments += "--network", $NetworkName, $Image

    $Result = Invoke-Command -Session $Session { docker @Using:Arguments ; $Global:LastExitCode }

    # Check for exit code
    if (0 -ne $Result[-1]) {
        throw "New-Container failed with the following output: $Result"
    }

    # Return created container id
    return $Result[0]
}
