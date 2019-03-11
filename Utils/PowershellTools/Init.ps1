# Enable all invoked commands tracing for debugging purposes
if ($true -eq $Env:ENABLE_TRACE) {
    Set-PSDebug -Trace 1
}

Set-StrictMode -Version Latest

# Refresh Path
$Env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")

# Stop script on error
$ErrorActionPreference = "Stop"
