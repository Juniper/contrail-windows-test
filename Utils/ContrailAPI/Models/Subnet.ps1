class Subnet {
    [String] $IpPrefix
    [Int] $IpPrefixLen
    [String] $DefaultGateway
    [String] $AllocationPoolsStart
    [String] $AllocationPoolsEnd
    [Bool] $DHCP = $true

    Subnet([String] $IpPrefix, [int] $IpPrefixLen,
        [String] $DefaultGateway, [String] $AllocationPoolsStart,
        [String] $AllocationPoolsEnd) {
        $this.IpPrefix = $IpPrefix
        $this.IpPrefixLen = $IpPrefixLen
        $this.DefaultGateway = $DefaultGateway
        $this.AllocationPoolsStart = $AllocationPoolsStart
        $this.AllocationPoolsEnd = $AllocationPoolsEnd
    }
}
