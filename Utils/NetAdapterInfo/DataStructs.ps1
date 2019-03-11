

class NetAdapterMacAddresses {
    [string] $MACAddress;
    [string] $MACAddressWindows;
}

class NetAdapterInformation : NetAdapterMacAddresses {
    [int] $IfIndex;
    [string] $IfName;
}

class VMNetAdapterInformation : NetAdapterMacAddresses {
    [string] $GUID;
}

class ContainerNetAdapterInformation : NetAdapterInformation {
    [string] $AdapterShortName;
    [string] $AdapterFullName;
    [string] $IPAddress;
    [int] $MtuSize;
}
