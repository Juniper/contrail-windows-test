. $PSScriptRoot\..\Testenv\Testbed.ps1
. $PSScriptRoot\..\Testenv\Configs.ps1
. $PSScriptRoot\..\..\PesterLogger\PesterLogger.ps1
. $PSScriptRoot\..\ComputeNode\Installation.ps1
. $PSScriptRoot\..\ContrailAPI\ContrailAPI.ps1
. $PSScriptRoot\..\ContrailAuthentication\Noauth.ps1
. $PSScriptRoot\..\ContrailAuthentication\Keystone.ps1

# Import order is chosen explicitly because of class dependency
. $PSScriptRoot\MultiNode.ps1

function New-MultiNodeSetup {
    Param (
        [Parameter(Mandatory = $true)] [Testbed[]] $Testbeds,
        [Parameter(Mandatory = $true)] [ControllerConfig] $ControllerConfig,
        [Parameter(Mandatory = $false)] [PSobject] $AuthConfig,
        [Parameter(Mandatory = $true)] [String] $ContrailProject,
        [Parameter(Mandatory = $true)] [CleanupStack] $CleanupStack
    )

    $Authenticator = [AuthenticatorFactory]::GetAuthenticator($ControllerConfig.AuthMethod, $AuthConfig)
    $ContrailRestApi = [ContrailRestApi]::new($ControllerConfig.RestApiUrl(), $Authenticator)
    $ContrailRepo = [ContrailRepo]::new($ContrailRestApi)
    $CleanupStack.ContrailRepo = $ContrailRepo

    Write-Log "Adding project '$ContrailProject' to Contrail"
    $Project = [Project]::new($ContrailProject)
    $ContrailRepo.AddOrReplace($Project) | Out-Null
    $CleanupStack.Push($Project)

    Write-Log 'Adding SecurityGroup to Contrail project'
    $SecurityGroup = [SecurityGroup]::new_Default($ContrailProject)
    $ContrailRepo.AddOrReplace($SecurityGroup) | Out-Null
    $CleanupStack.Push($SecurityGroup)

    $VRouters = @()
    foreach ($Testbed in $Testbeds) {
        Write-Log "Creating virtual router. Name: $($Testbed.Name); Address: $($Testbed.Address)"
        $VirtualRouter = [VirtualRouter]::new($Testbed.Name, $Testbed.Address)
        $Response = $ContrailRepo.AddOrReplace($VirtualRouter)
        Write-Log "Reported UUID of new virtual router: $($Response.'virtual-router'.'uuid')"
        $VRouters += $VirtualRouter
        $CleanupStack.Push($VirtualRouter)
    }

    return [MultiNode]::New($ContrailRestApi, $VRouters, $Project)
}
