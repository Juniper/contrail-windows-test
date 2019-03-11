. $PSScriptRoot\..\..\Utils\PowershellTools\Aliases.ps1
. $PSScriptRoot\Impl.ps1

function Get-RemoteNetAdapterInformation {
    Param ([Parameter(Mandatory = $true)] [PSSessionT] $Session,
           [Parameter(Mandatory = $true)] [string] $AdapterName)

    $NetAdapterInformation = Invoke-Command -Session $Session -ScriptBlock {
        $Res = Get-NetAdapter -IncludeHidden -Name $Using:AdapterName | Select-Object ifName,MacAddress,ifIndex

        return @{
            IfIndex = $Res.IfIndex;
            IfName = $Res.ifName;
            MACAddress = $Res.MacAddress.Replace("-", ":").ToLower();
            MACAddressWindows = $Res.MacAddress.ToLower();
        }
    }

    return [NetAdapterInformation] $NetAdapterInformation
}
