. $PSScriptRoot\..\..\Utils\PowershellTools\Aliases.ps1
. $PSScriptRoot\..\..\Utils\PowershellTools\Invoke-UntilSucceeds.ps1
. $PSScriptRoot\..\..\PesterLogger\PesterLogger.ps1

. $PSScriptRoot\Impl.ps1

function Get-RemoteContainerNetAdapterInformation {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $true)] [string] $ContainerID)

    $AdapterInfo = Invoke-UntilSucceeds -Duration 60 -Interval 5 -Name "waiting for container $ContainerID IP" {
        try {
            $RawAdapterInfo = Read-RawRemoteContainerNetAdapterInformation -Session $Session -ContainerID $ContainerID
            Assert-IsIpAddressInRawNetAdapterInfoValid -RawAdapterInfo $RawAdapterInfo
            $RawAdapterInfo
        } catch {
            Write-Log "Invalid remote IP: $( $_.Exception )"
            throw
        }
    }
    $Info = ConvertFrom-RawNetAdapterInformation -RawAdapterInfo $AdapterInfo
    return [ContainerNetAdapterInformation] $Info
}
