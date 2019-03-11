. $PSScriptRoot\..\..\Utils\PowershellTools\Aliases.ps1
. $PSScriptRoot\..\..\Utils\PowershellTools\Invoke-NativeCommand.ps1
. $PSScriptRoot\..\..\PesterLogger\PesterLogger.ps1
. $PSScriptRoot\Configuration.ps1
. $PSScriptRoot\Service.ps1

function Invoke-MsiExec {
    Param (
        [Switch] $Uninstall,
        [Parameter(Mandatory = $true)] [PSSessionT] $Session,
        [Parameter(Mandatory = $true)] [String] $Path
    )

    $Action = if ($Uninstall) { "/x" } else { "/i" }

    Write-Log "Running msiexec $Action $(Split-Path $Path -Leaf)"

    Invoke-Command -Session $Session -ScriptBlock {
        # Get rid of all leftover handles to the Service objects
        [System.GC]::Collect()

        $Result = Start-Process msiexec.exe -ArgumentList @($Using:Action, $Using:Path, "/quiet") `
            -Wait -PassThru

        # Do not fail while uninstaling MSIs that are not currently installed
        $MsiErrorUnknownProduct = 1605
        if ($Using:Uninstall -and ($Result.ExitCode -eq $MsiErrorUnknownProduct)) {
            return
        }

        if (0 -ne $Result.ExitCode) {
            $WhatWentWrong = if ($Using:Uninstall) {"Uninstallation"} else {"Installation"}
            throw "$WhatWentWrong of $Using:Path failed with $($Result.ExitCode)"
        }

        # Refresh Path
        $Env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    }
}

function Install-Agent {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    Write-Log "Installing Agent"
    Invoke-MsiExec -Session $Session -Path "C:\Artifacts\agent\contrail-vrouter-agent.msi"

    try {
        New-AgentService -Session $Session
    }
    catch {
        Invoke-MsiExec -Uninstall -Session $Session -Path "C:\Artifacts\agent\contrail-vrouter-agent.msi"
        throw
    }
}

function Uninstall-Agent {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    Write-Log "Uninstalling Agent"

    Remove-AgentService -Session $Session
    Invoke-MsiExec -Uninstall -Session $Session -Path "C:\Artifacts\agent\contrail-vrouter-agent.msi"
}

function Install-Extension {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    Write-Log "Installing vRouter Forwarding Extension"
    Invoke-MsiExec -Session $Session -Path "C:\Artifacts\vRouter\vRouter.msi"
}

function Uninstall-Extension {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    Write-Log "Uninstalling vRouter Forwarding Extension"
    Invoke-MsiExec -Uninstall -Session $Session -Path "C:\Artifacts\vRouter\vRouter.msi"
}

function Install-Utils {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    Write-Log "Installing vRouter utility tools"
    Invoke-MsiExec -Session $Session -Path "C:\Artifacts\vRouter\utils.msi"
}

function Uninstall-Utils {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    Write-Log "Uninstalling vRouter utility tools"
    Invoke-MsiExec -Uninstall -Session $Session -Path "C:\Artifacts\vRouter\utils.msi"
}

function Install-CnmPlugin {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    Write-Log "Installing CNM Plugin"
    Invoke-MsiExec -Session $Session -Path "C:\Artifacts\cnm-plugin\contrail-cnm-plugin.msi"
    try {
        New-CNMPluginService -Session $Session
    }
    catch {
        Invoke-MsiExec -Uninstall -Session $Session -Path "C:\Artifacts\cnm-plugin\contrail-cnm-plugin.msi"
        throw
    }
}

function Uninstall-CnmPlugin {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    Write-Log "Uninstalling CNM plugin"

    Remove-CNMPluginService -Session $Session
    Invoke-MsiExec -Uninstall -Session $Session -Path "C:\Artifacts\cnm-plugin\contrail-cnm-plugin.msi"
}

function Install-Nodemgr {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    Write-Log "Installing Nodemgr"
    $Res = Invoke-NativeCommand -Session $Session -AllowNonZero -CaptureOutput -ScriptBlock {
        Get-ChildItem "C:\Artifacts\nodemgr\*.tar.gz" -Name
    }
    $Archives = $Res.Output
    $InstalledArchives = @()
    try {
        foreach($A in $Archives) {
            Write-Log "- (Nodemgr) Installing pip archive $A"
            Invoke-NativeCommand -Session $Session -CaptureOutput -ScriptBlock {
                pip install "C:\Artifacts\nodemgr\$Using:A"
            } | Out-Null
            $InstalledArchives += $A
        }

        New-NodeMgrService -Session $Session
    }
    catch {
        foreach($A in $InstalledArchives) {
            Write-Log "- (Nodemgr) Uninstalling pip package $A"
            Invoke-NativeCommand -Session $Session -CaptureOutput -ScriptBlock {
                pip uninstall "C:\Artifacts\nodemgr\$Using:A"
            } | Out-Null
        }
        throw
    }
}

function Uninstall-Nodemgr {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session)

    Write-Log "Uninstalling Nodemgr"

    Remove-NodeMgrService -Session $Session

    $Res = Invoke-NativeCommand -Session $Session -AllowNonZero -CaptureOutput -ScriptBlock {
        Get-ChildItem "C:\Artifacts\nodemgr\*.tar.gz" -Name
    }
    $Archives = $Res.Output
    foreach($P in $Archives) {
        Write-Log "- (Nodemgr) Uninstalling pip package $P"
        Invoke-NativeCommand -Session $Session -CaptureOutput -ScriptBlock {
            pip uninstall "C:\Artifacts\nodemgr\$Using:P"
        }
    }
}

function Install-Components {
    Param (
        [Parameter(Mandatory = $true)] [Testbed] $Testbed,
        [Parameter(Mandatory = $true)] [CleanupStack] $CleanupStack
    )

    Install-Extension -Session $Testbed.GetSession()
    $CleanupStack.Push(${function:Uninstall-Extension}, @($Testbed))
    Install-CnmPlugin -Session $Testbed.GetSession()
    $CleanupStack.Push(${function:Uninstall-CnmPlugin}, @($Testbed))
    Install-Agent -Session $Testbed.GetSession()
    $CleanupStack.Push(${function:Uninstall-Agent}, @($Testbed))
    Install-Utils -Session $Testbed.GetSession()
    $CleanupStack.Push(${function:Uninstall-Utils}, @($Testbed))
    Install-Nodemgr -Session $Testbed.GetSession()
    $CleanupStack.Push(${function:Uninstall-Nodemgr}, @($Testbed))
}
