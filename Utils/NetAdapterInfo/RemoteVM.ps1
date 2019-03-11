. $PSScriptRoot\..\..\Utils\PowershellTools\Aliases.ps1
. $PSScriptRoot\..\..\Utils\PowershellTools\Init.ps1
. $PSScriptRoot\Impl.ps1

function Get-RemoteVMNetAdapterInformation {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $true)] [string] $VMName,
           [Parameter(Mandatory = $true)] [string] $AdapterName)

    $NetAdapterInformation = Invoke-Command -Session $Session -ScriptBlock {
        $NetAdapter = Get-VMNetworkAdapter -VMName $Using:VMName -Name $Using:AdapterName
        $MacAddress = $NetAdapter.MacAddress -Replace '..(?!$)', '$&-'
        $GUID = $NetAdapter.Id.ToLower().Replace('microsoft:', '').Replace('\', '--')

        return @{
            MACAddress = $MacAddress.Replace("-", ":");
            MACAddressWindows = $MacAddress;
            GUID = $GUID
        }
    }

    return [VMNetAdapterInformation] $NetAdapterInformation
}
