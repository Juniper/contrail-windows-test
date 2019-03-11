class Testenv {
    [SystemConfig] $System
    [OpenStackConfig] $OpenStack
    [ControllerConfig] $Controller
    [Testbed[]] $Testbeds

    [System.Collections.Stack] $CleanupStacks = [System.Collections.Stack]::new()
    [LogSource[]] $LogSources = $null
    [ContrailRestApi] $ContrailRestApi = $null
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
        try {
            Sync-MicrosoftDockerImagesOnTestbeds -Testbeds $this.Testbeds
        }
        catch {
            Write-Host 'Unable to update Microsoft docker images'
        }

        Write-Log 'Setting up Contrail'
        $this.InitializeContrail($ContrailProject, $InstallComponents, $CleanupStack)

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

    hidden [void] InitializeContrail ([String] $ContrailProject, [Bool] $InstallComponents, [CleanupStack] $CleanupStack) {
        $Authenticator = [AuthenticatorFactory]::GetAuthenticator($this.Controller.AuthMethod, $this.OpenStack)
        $this.ContrailRestApi = [ContrailRestApi]::new($this.Controller.RestApiUrl(), $Authenticator)
        $this.ContrailRepo = [ContrailRepo]::new($this.ContrailRestApi)
        $CleanupStack.ContrailRepo = $this.ContrailRepo

        Write-Log "Adding project '$ContrailProject' to Contrail"
        $Project = [Project]::new($ContrailProject)
        $this.ContrailRepo.AddOrReplace($Project) | Out-Null
        $CleanupStack.Push($Project)

        Write-Log 'Adding SecurityGroup to Contrail project'
        $SecurityGroup = [SecurityGroup]::new_Default($ContrailProject)
        $this.ContrailRepo.AddOrReplace($SecurityGroup) | Out-Null
        $CleanupStack.Push($SecurityGroup)

        if ($InstallComponents) {
            foreach ($Testbed in $this.Testbeds) {
                Write-Log "Creating virtual router. Name: $($Testbed.Name); Address: $($Testbed.Address)"
                $VirtualRouter = [VirtualRouter]::new($Testbed.Name, $Testbed.Address)
                $Response = $this.ContrailRepo.AddOrReplace($VirtualRouter)
                Write-Log "Reported UUID of new virtual router: $($Response.'virtual-router'.'uuid')"
                $CleanupStack.Push($VirtualRouter)
            }
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
