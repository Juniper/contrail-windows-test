function Read-TestenvFile([string] $Path) {
    if (-not (Test-Path $Path)) {
        throw [System.Management.Automation.ItemNotFoundException] "Testenv config file not found at specified location."
    }
    $FileContents = Get-Content -Path $Path -Raw
    $Parsed = ConvertFrom-Yaml $FileContents
    return $Parsed
}

. $PSScriptRoot\ControllerConfig.ps1
. $PSScriptRoot\OpenStackConfig.ps1
. $PSScriptRoot\SystemConfig.ps1
