. $PSScriptRoot\..\..\PesterLogger\PesterLogger.ps1
. $PSScriptRoot\..\..\Utils\PowershellTools\Invoke-NativeCommand.ps1
. $PSScriptRoot\..\Testenv\Testbed.ps1
. $PSScriptRoot\Configuration.ps1

class Service {
    [String] $ServiceName;
    [String] $ExecutablePath;
    [Hashtable] $AdditionalParams;

    [Void] init([String] $ServiceName, [String] $ExecutablePath, [Hashtable] $AdditionalParams) {
        $this.ServiceName = $ServiceName
        $this.ExecutablePath = $ExecutablePath
        $this.AdditionalParams = $AdditionalParams
    }

    Service ([String] $ServiceName, [String] $ExecutablePath, [Hashtable] $AdditionalParams) {
        $this.init($ServiceName, $ExecutablePath, $AdditionalParams)
    }
}

function Install-ServiceWithNSSM {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session,
        [Parameter(Mandatory=$true)] [Service] $Configuration
    )

    Write-Log "Installing service $($Configuration.ServiceName)"
    $Output = Invoke-NativeCommand -Session $Session -ScriptBlock {
        nssm install $Using:Configuration.ServiceName $Using:Configuration.ExecutablePath
    } -AllowNonZero -CaptureOutput

    $NSSMServiceAlreadyCreatedError = 5
    if (0 -eq $Output.ExitCode) {
        Write-Log $Output.Output
    }
    elseif ($Output.ExitCode -eq $NSSMServiceAlreadyCreatedError) {
        Write-Log "$($Configuration.ServiceName) service already created, continuing..."
    }
    else {
        $ExceptionMessage = @"
Unknown (wild) error appeared while creating $($Configuration.ServiceName) service.
ExitCode: $($Output.ExitCode)
NSSM output: $($Output.Output)
"@
        throw [HardError]::new($ExceptionMessage)
    }

    ForEach ($Pair in $Configuration.AdditionalParams.GetEnumerator()) {
        $Output = Invoke-NativeCommand -Session $Session -ScriptBlock {
            nssm set $Using:Configuration.ServiceName $Using:Pair.Name $Using:Pair.Value
        } -CaptureOutput

        Write-Log $Output.Output
    }
}

function Remove-ServiceWithNSSM {
    Param (
        [Parameter(Mandatory=$true)] $Session,
        [Parameter(Mandatory=$true)] $ServiceName
    )

    Write-Log "Uninstalling service $ServiceName"

    $Output = Invoke-NativeCommand -Session $Session {
        nssm remove $using:ServiceName confirm
    } -CaptureOutput

    Write-Log $Output.Output
}

function Start-RemoteService {
    Param (
        [Parameter(Mandatory=$true)] $Session,
        [Parameter(Mandatory=$true)] $ServiceName
    )

    Write-Log "Starting $ServiceName"

    Invoke-Command -Session $Session -ScriptBlock {
        Start-Service $using:ServiceName
    } | Out-Null
}

function Stop-RemoteService {
    Param (
        [Parameter(Mandatory=$true)] $Session,
        [Parameter(Mandatory=$true)] $ServiceName
    )

    Write-Log "Stopping $ServiceName"

    Invoke-Command -Session $Session -ScriptBlock {
        # Some tests which don't use all components, use Clear-TestConfiguration function.
        # Ignoring errors here allows us to get rid of boilerplate code, which
        # would be needed to handle cases where not all services are present on testbed(s).
        Stop-Service $using:ServiceName -ErrorAction SilentlyContinue
    } | Out-Null
}

function Get-ServiceStatus {
    Param (
        [Parameter(Mandatory=$true)] $Session,
        [Parameter(Mandatory=$true)] $ServiceName
    )

    Invoke-Command -Session $Session -ScriptBlock {
        $Service = Get-Service $using:ServiceName -ErrorAction SilentlyContinue
        if ($Service -and $Service.Status) {
            return $Service.Status.ToString()
        } else {
            return $null
        }
    }
}

function Get-NodeMgrLogPath {
    return Join-Path (Get-ComputeLogsDir) "contrail-vrouter-nodemgr.log"
}

function Get-VrouterLogPath {
    return Join-Path (Get-ComputeLogsDir) "vrouter.log"
}

function Get-AgentLogPath {
    return Join-Path (Get-ComputeLogsDir) "contrail-vrouter-agent-service.log"
}

function Get-CNMPluginLogPath {
    return Join-Path (Get-ComputeLogsDir) "contrail-cnm-plugin.log"
}

function Get-CNMPluginServiceLogPath {
    return Join-Path (Get-ComputeLogsDir) "contrail-cnm-plugin-service.log"
}

function Get-ServicesLogPaths {
    return @((Get-VrouterLogPath), (Get-AgentLogPath), (Get-CNMPluginLogPath), (Get-CNMPluginServiceLogPath), (Get-NodeMgrLogPath))
}

function Get-AgentServiceName {
    return 'contrail-vrouter-agent'
}

function Get-CNMPluginServiceName {
    return 'contrail-cnm-plugin'
}

function Get-NodeMgrServiceName {
    return 'contrail-vrouter-nodemgr'
}

function Test-IsCNMPluginServiceRunning {
    Param (
        [Parameter(Mandatory=$true)] $Session
    )

    $ServiceName = Get-CNMPluginServiceName
    return $("Running" -eq (Get-ServiceStatus -ServiceName $ServiceName -Session $Session))
}

function New-AgentService {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session
    )

    $AdditionalParams = @{
        'AppDirectory' = 'C:\Program Files\Juniper Networks\Agent'
        'AppParameters' = '-NoProfile -File entrypoint.ps1'
        'AppStdout' = (Get-AgentLogPath)
        'AppStderr' = (Get-AgentLogPath)
    }
    $Configuration = [Service]::new(
        (Get-AgentServiceName),
        'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
        $AdditionalParams
    )
    Install-ServiceWithNSSM `
        -Session $Session `
        -Configuration $Configuration
}

function New-CNMPluginService {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session
    )

    $AdditionalParams = @{
        'AppStdout' = (Get-CNMPluginServiceLogPath)
        'AppStderr' = (Get-CNMPluginServiceLogPath)
    }
    $Configuration = [Service]::new(
        (Get-CNMPluginServiceName),
        'C:\Program Files\Juniper Networks\cnm-plugin\contrail-cnm-plugin.exe',
        $AdditionalParams
    )
    Install-ServiceWithNSSM `
        -Session $Session `
        -Configuration $Configuration
}

function New-NodeMgrService {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session
    )

    $AdditionalParams = @{
        'AppParameters' = '--nodetype contrail-vrouter'
        'AppStdout' = (Get-NodeMgrLogPath)
        'AppStderr' = (Get-NodeMgrLogPath)
    }
    $Configuration = [Service]::new(
        (Get-NodeMgrServiceName),
        'C:\Python27\Scripts\contrail-nodemgr.exe',
        $AdditionalParams
    )
    Install-ServiceWithNSSM `
        -Session $Session `
        -Configuration $Configuration
}

function Start-AgentService {
    Param (
        [Parameter(Mandatory=$true)] $Session
    )

    Start-RemoteService -Session $Session -ServiceName $(Get-AgentServiceName)
}

function Start-CNMPluginService {
    Param (
        [Parameter(Mandatory=$true)] $Session
    )

    Start-RemoteService -Session $Session -ServiceName $(Get-CNMPluginServiceName)
}

function Start-NodeMgrService {
    Param (
        [Parameter(Mandatory=$true)] $Session
    )

    Start-RemoteService -Session $Session -ServiceName $(Get-NodeMgrServiceName)
}


function Stop-CNMPluginService {
    Param (
        [Parameter(Mandatory=$true)] $Session
    )

    Stop-RemoteService -Session $Session -ServiceName (Get-CNMPluginServiceName)
}

function Stop-AgentService {
    Param (
        [Parameter(Mandatory=$true)] $Session
    )

    Stop-RemoteService -Session $Session -ServiceName (Get-AgentServiceName)
}

function Stop-NodeMgrService {
    Param (
        [Parameter(Mandatory=$true)] $Session
    )

    Stop-RemoteService -Session $Session -ServiceName (Get-NodeMgrServiceName)
}

function Remove-CNMPluginService {
    Param (
        [Parameter(Mandatory=$true)] $Session
    )

    $ServiceName = Get-CNMPluginServiceName
    $ServiceStatus = Get-ServiceStatus -ServiceName $ServiceName -Session $Session

    if ("Stopped" -ne $ServiceStatus) {
        Stop-CNMPluginService -Session $Session
    }

    Remove-ServiceWithNSSM -Session $Session -ServiceName $ServiceName
}

function Remove-AgentService {
    Param (
        [Parameter(Mandatory=$true)] $Session
    )

    $ServiceName = Get-AgentServiceName
    $ServiceStatus = Get-ServiceStatus -Session $Session -ServiceName $ServiceName

    if ("Stopped" -ne $ServiceStatus) {
        Stop-AgentService -Session $Session
    }

    Remove-ServiceWithNSSM -Session $Session -ServiceName $ServiceName
}

function Remove-NodeMgrService {
    Param (
        [Parameter(Mandatory=$true)] $Session
    )

    $ServiceName = Get-NodeMgrServiceName
    $ServiceStatus = Get-ServiceStatus -Session $Session -ServiceName $ServiceName

    if ("Stopped" -ne $ServiceStatus) {
        Stop-NodeMgrService -Session $Session
    }

    Remove-ServiceWithNSSM -Session $Session -ServiceName $ServiceName
}
