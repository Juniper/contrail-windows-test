class Testenv {
    [SystemConfig] $System
    [OpenStackConfig] $OpenStack
    [ControllerConfig] $Controller
    [Testbed[]] $Testbeds

    [System.Collections.Stack] $CleanupStacks = [System.Collections.Stack]::new()
    [MultiNode] $Multinode = $null
    [LogSource[]] $LogSources = $null
    [ContrailRepo] $ContrailRepo = $null

    Initialize([String] $TestenvConfFile, [String] $LogDir, [String] $ContrailProject, [Bool] $InstallComponents) {
        Initialize-PesterLogger -OutDir $LogDir

        Write-Log 'Reading config files'
        $this.System = [SystemConfig]::LoadFromFile($TestenvConfFile)
        $this.OpenStack = [OpenStackConfig]::LoadFromFile($TestenvConfFile)
        $this.Controller = [ControllerConfig]::LoadFromFile($TestenvConfFile)
        $this.Testbeds = [Testbed]::LoadFromFile($TestenvConfFile)

        $CleanupStack = $this.NewCleanupStack()

        Write-Log 'Creating sessions'
        $CleanupStack.Push( {Param([Testbed[]] $Testbeds) foreach ($Testbed in $Testbeds) { $Testbed.RemoveAllSessions() }}, @(, $this.Testbeds))

        Write-Log 'Preparing testbeds'
        Set-ConfAndLogDir -Testbeds $this.Testbeds
        Sync-MicrosoftDockerImagesOnTestbeds -Testbeds $this.Testbeds

        Write-Log 'Setting up Contrail'
        $this.MultiNode = New-MultiNodeSetup `
            -Testbeds $this.Testbeds `
            -ControllerConfig $this.Controller `
            -AuthConfig $this.OpenStack `
            -ContrailProject $ContrailProject `
            -CleanupStack $CleanupStack
        $this.ContrailRepo = [ContrailRepo]::new($this.MultiNode.ContrailRestApi)

        Write-Log 'Creating log sources'
        [LogSource[]] $this.LogSources = New-ComputeNodeLogSources -Testbeds $this.Testbeds
        if ($InstallComponents) {
            $CleanupStack.Push(${function:Clear-Logs}, @(, $this.LogSources))
        }
        $CleanupStack.Push(${function:Merge-Logs}, @(, $this.LogSources))

        if ($InstallComponents) {
            foreach ($Testbed in $this.Testbeds) {
                Initialize-ComputeNode `
                    -Testbed $Testbed `
                    -Configs $this `
                    -CleanupStack $CleanupStack

                $CleanupStack.Push(${function:Remove-AllUnusedDockerNetworks}, @($Testbed))
            }
            $CleanupStack.Push(${function:Remove-AllContainers}, @(, $this.Testbeds))
        }
    }

    [CleanupStack] NewCleanupStack() {
        $CleanupStack = [CleanupStack]::new()
        $this.CleanupStacks.Push($CleanupStack)
        return $CleanupStack
    }

    [Void] Cleanup() {
        Write-Log 'Testenv.Cleanup() started'
        foreach ($CleanupStack in $this.CleanupStacks) {
            $CleanupStack.RunCleanup($this.ContrailRepo)
        }
    }
}

# This is legacy alias for $Testbeds field
Update-TypeData -TypeName 'Testenv' -MemberType 'AliasProperty' -MemberName 'Sessions' -Value 'Testbeds' -ErrorAction 'SilentlyContinue'
