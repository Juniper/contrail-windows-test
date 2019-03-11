. $PSScriptRoot\..\..\Utils\PowershellTools\Aliases.ps1
. $PSScriptRoot\DataStructs.ps1

function Read-RawRemoteContainerNetAdapterInformation {
    Param (
        [Parameter(Mandatory = $true)] [PSSessionT] $Session,
        [Parameter(Mandatory = $true)] [string] $ContainerID
    )

    $JsonAdapterInfo = Invoke-Command -Session $Session -ScriptBlock {

        $RemoteCommand = {
            $Adapter = (Get-NetAdapter -Name 'vEthernet (*)')[0]
            $Info = $Adapter | Select-Object 'ifIndex', 'Name', 'MacAddress', 'MtuSize'
            Add-Member -InputObject $Info -MemberType NoteProperty `
                -Name 'IPAddress' -Value ($Adapter | Get-NetIPAddress -AddressFamily IPv4).IPAddress
            return $Info | ConvertTo-Json -Depth 5
        }.ToString()

        $Info = (docker exec $Using:ContainerID powershell $RemoteCommand) | ConvertFrom-Json
        Add-Member -InputObject $Info -MemberType NoteProperty `
            -Name 'ifName' -Value (Get-NetAdapter -IncludeHidden -Name $Info.Name).ifName
        return $Info
    }

    return $JsonAdapterInfo
}

function Assert-IsIpAddressInRawNetAdapterInfoValid {
    Param (
        [Parameter(Mandatory = $true)] [PSCustomObject] $RawAdapterInfo
    )

    if (!$RawAdapterInfo.IPAddress -or ($RawAdapterInfo.IPAddress -isnot [string])) {
        throw "Invalid IPAddress returned from container: $($RawAdapterInfo.IPAddress | ConvertTo-Json)"
    }

    if ($RawAdapterInfo.IPAddress -Match '^169\.254') {
        throw "Container reports an autoconfiguration IP address: $( $RawAdapterInfo.IPAddress )"
    }
}

function ConvertFrom-RawNetAdapterInformation {
    Param (
        [Parameter(Mandatory = $true)] [PSCustomObject] $RawAdapterInfo
    )

    $AdapterInfo = @{
        ifIndex = $RawAdapterInfo.ifIndex
        ifName = $RawAdapterInfo.ifName
        AdapterFullName = $RawAdapterInfo.Name
        AdapterShortName = [regex]::new('vEthernet \((.*)\)').Replace($RawAdapterInfo.Name, '$1')
        MacAddressWindows = $RawAdapterInfo.MacAddress.ToLower()
        IPAddress = $RawAdapterInfo.IPAddress
        MtuSize = $RawAdapterInfo.MtuSize
    }

    $AdapterInfo.MacAddress = $AdapterInfo.MacAddressWindows.Replace('-', ':')

    return $AdapterInfo
}
