. $PSScriptRoot/Aliases.ps1
function Invoke-NativeCommand {
    Param (
        [Parameter(Mandatory = $true)] [ScriptBlock] $ScriptBlock,
        [Parameter(Mandatory = $false)] [PSSessionT] $Session,
        [Switch] $AllowNonZero,
        [Switch] $CaptureOutput
    )
    # Utility wrapper.
    # We encountered issues when trying to run non-powershell commands in a script, when it's
    # called from Jenkinsfile.
    # Everything that is printed to stderr in those external commands immediately causes an
    # exception to be thrown (as well as kills the command).
    # We don't want this, but we also want to know whether the command was successful or not.
    # This is what this wrapper aims to do.
    #
    # This wrapper will throw only if the whole command failed. It will suppress any exceptions
    # when the command is running.
    #
    # Also, **every** execution of any native command should use this wrapper,
    # because Jenkins misinterprets $LastExitCode variable.
    #
    # Note: The command has to return 0 exitcode to be considered successful.
    #
    # The wrapper returns a dictionary with a two optional fields:
    # If -AllowNonZero is set, the .ExitCode contains an exitcode of a command.
    # If -CaputerOutput is set, the .Output contains captured output
    # (otherwise, it will be printed usint Write-Host)

    # Helpers -------------------------------------------------------------------------------------

    function Invoke-CommandOnExecutor([ScriptBlock] $ScriptBlock) {
        if ($Session) {
            Invoke-Command -Session $Session -ScriptBlock $ScriptBlock
        } else {
            Invoke-Command -ScriptBlock $ScriptBlock
        }
    }
    function Push-RemoteErrorActionPreference([String] $ErrorAction) {
        Invoke-Command -Session $Session {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                "PSUseDeclaredVarsMoreThanAssignments", "",
                Justification="It's actually used in Pop-RemoteErrorActionPreference"
            )]
            $InvokeNativeCommandSavedErrorAction = $ErrorActionPreference
            $ErrorActionPreference = $Using:ErrorAction
        }
    }

    function Pop-RemoteErrorActionPreference {
        Invoke-Command -Session $Session {
            $ErrorActionPreference = $InvokeNativeCommandSavedErrorAction
        }
    }

    # End helpers ---------------------------------------------------------------------------------

    # If an executable in $ScriptBlock wouldn't be found then while checking $LastExitCode
    # we would be checking the exit code of a previous command. To avoid this we clear $LastExitCode.
    Invoke-CommandOnExecutor { $Global:LastExitCode = $null }

    # Since we're redirecting stderr to stdout we shouldn't have to set ErrorActionPreference
    # but because of a bug in Powershell we have to.
    # https://github.com/PowerShell/PowerShell/issues/4002
    if ($Session) { Push-RemoteErrorActionPreference "Continue" }
    # Local ErrorActionPreference is local to a function,
    # so it doesn't need to be saved and restored.
    $ErrorActionPreference = "Continue"

    try {
        # We redirect stderr to stdout so nothing is added to $Error.
        # We do this to be compliant to durable-task-plugin 1.18.
        if ($CaptureOutput) {
            $Output = @()
            $Output += Invoke-CommandOnExecutor -ScriptBlock $ScriptBlock 2>&1
        } else {
            Invoke-CommandOnExecutor -ScriptBlock $ScriptBlock 2>&1 | Write-Host
        }
    }
    finally {
        if ($Session) { Pop-RemoteErrorActionPreference }
        $ErrorActionPreference = "Stop"
    }

    $ExitCode = Invoke-CommandOnExecutor { $Global:LastExitCode }

    # We clear it to be compliant with durable-task-plugin up to 1.17
    # (that's needed to be done only on the local machine)
    $Global:LastExitCode = $null

    if ($false -eq $AllowNonZero -and 0 -ne $ExitCode) {
        if ($CaptureOutput) {
            $Output | Write-Host
        }
        throw "Command ``$ScriptBlock`` failed with exitcode: $ExitCode"
    }

    $ReturnDict = @{}

    if ($AllowNonZero) { $ReturnDict.ExitCode = $ExitCode }
    if ($CaptureOutput) { $ReturnDict.Output = $Output }

    return $ReturnDict
}
