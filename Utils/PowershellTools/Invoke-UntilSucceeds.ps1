. $PSScriptRoot\Aliases.ps1
. $PSScriptRoot\Exceptions.ps1
. $PSScriptRoot\..\..\PesterLogger\PesterLogger.ps1

class HardError : System.Exception {
    HardError([string] $msg) : base($msg) {}
    HardError([string] $msg, [System.Exception] $inner) : base($msg, $inner) {}
}

function Invoke-UntilSucceeds {
    <#
    .SYNOPSIS
    Repeatedly calls a script block as a job until its return value evaluates to true. Subsequent calls
    happen after Interval seconds. Will catch any exceptions that occur in the meantime.
    If the exception being thrown is a HardError, no further retry attempps will be made.
    User has to specify a timeout after which the function fails by setting the Duration (or NumRetires) parameter.
    If the function fails, it throws an exception containing the last reason of failure.

    Invoke-UntilSucceeds can work in two modes: number of retries limit (-NumRetries)
    or retrying until timeout (-Duration). When Duration is set,
    it is guaranteed that that if Invoke-UntilSucceeds had failed and precondition was true,
    there was at least one check performed at time T where T >= T_start + Duration.

    .PARAMETER ScriptBlock
    ScriptBlock to repeatedly call.
    .PARAMETER Interval
    Interval (in seconds) between retries.
    .PARAMETER Duration
    Timeout (in seconds).
    .PARAMETER NumRetries
    Maximum number of retries to perform.
    .PARAMETER Name
    Name of the function to be used in exceptions' messages.
    .Parameter AssumeTrue
    If set, Invoke-UntilSucceeds doesn't check the returned value at all
    (it will still treat exceptions as failure though).
    #>
    Param (
        [Parameter(Mandatory=$true,
                   ValueFromPipeline=$true)] [ScriptBlock] $ScriptBlock,
        [Parameter(Mandatory=$false)] [int] $Interval = 1,
        [Parameter(Mandatory=$false)] [int] $Duration,
        [Parameter(Mandatory=$false)] [int] $NumRetries,
        [Parameter(Mandatory=$false)] [ScriptBlock] $Precondition,
        [Parameter(Mandatory=$false)] [String] $Name = "Invoke-UntilSucceds",
        [Switch] $AssumeTrue
    )

    $DebugTag = "[DEBUG Invoke-UntilSucceeds]"

    Write-Log "$DebugTag Function begins with job: $name"
    Write-Log "$DebugTag Duration: $Duration; NumRetries $NumRetries"
    if ((-not $Duration) -and (-not $NumRetries)) {
        throw "Either non-zero -Duration or -NumRetries has to be specified"
    }

    if ($Duration) {
        if ($NumRetries) {
            throw "-Duration can't be used with -Retries"
        }

        if ($Duration -lt $Interval) {
            throw "Duration must be longer than interval"
        }
    }

    if (0 -eq $Interval) {
        throw "Interval must not be equal to zero"
    }
    $StartTime = Get-Date
    Write-Log "$DebugTag Checks passed. Start time: --$StartTime--"
    $NumRetry = 0

    while ($true) {
        $NumRetry += 1
        Write-Log "$DebugTag Trying to run number $NumRetry"
        $LastCheck = if ($Duration) {
            $TimeElapsed = ((Get-Date) - $StartTime).TotalSeconds
            Write-Log "$DebugTag TimeElapsed: $TimeElapsed"
            $TimeElapsed -ge $Duration
        } else {
            $NumRetry -eq $NumRetries
        }

        try {
            Write-Log "$DebugTag Running task. LastCheck: $LastCheck"

            $Runspace = [RunspaceFactory]::CreateRunspace()
            $Runspace.Open()

            $Exception = $null
            $Runspace.SessionStateProxy.SetVariable('ScriptBlock', $ScriptBlock)
            $Runspace.SessionStateProxy.SetVariable('Exception', [ref]$Exception)

            $PowerShellThread = [PowerShell]::Create().AddScript( {
                    try {
                        . $ScriptBlock
                    }
                    catch {
                        $Exception.Value = $_.Exception
                    }
                })
            $PowerShellThread.Runspace = $Runspace

            $TimeElapsed = ((Get-Date) - $StartTime).TotalSeconds
            Write-Log "$DebugTag Starting thread. TimeElapsed: $TimeElapsed"
            $ThreadHandle = $PowerShellThread.BeginInvoke()

            if ($Duration) {
                [System.Threading.WaitHandle]::WaitAny($ThreadHandle.AsyncWaitHandle, $Duration * 1000) | Out-Null
                $TimeElapsed = ((Get-Date) - $StartTime).TotalSeconds
                Write-Log "$DebugTag Finished waiting thread. TimeElapsed: $TimeElapsed"
                if (-not $ThreadHandle.IsCompleted) {
                    $PowerShellThread.Stop()
                    $TimeElapsed = ((Get-Date) - $StartTime).TotalSeconds
                    throw "Job didn't finish in $Duration seconds. After $TimeElapsed we stopped trying."
                }
            }
            else {
                [System.Threading.WaitHandle]::WaitAny($ThreadHandle.AsyncWaitHandle) | Out-Null
            }

            if ($null -ne $Exception) {
                throw $Exception
            }
            $ReturnVal = $PowerShellThread.EndInvoke($ThreadHandle)

            Write-Log "$DebugTag Task returned with ReturnVal: $ReturnVal"
            if ($AssumeTrue -or $ReturnVal) {
                Write-Log "$DebugTag Returning value"
                return $ReturnVal
            } else {
                throw [CITimeoutException]::new(
                    "${Name}: Did not evaluate to True. Last return value encountered was: $ReturnVal."
                )
            }
        } catch [HardError] {
            Write-Log "$DebugTag Caught HardError. $($_.Exception.InnerException)"
            throw [CITimeoutException]::new(
                "${Name}: Stopped retrying because HardError was thrown",
                $_.Exception.InnerException
            )
        } catch {
            Write-Log "$DebugTag Caught 'soft' exception. $($_.Exception)"
            if ($LastCheck) {
                throw [CITimeoutException]::new("$Name failed.", $_.Exception)
            } else {
                Write-Log "$DebugTag Going to sleep for: $Interval seconds"
                Start-Sleep -Seconds $Interval
            }
        }
    }
}
