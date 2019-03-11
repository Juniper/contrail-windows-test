class PortRange {
    [Int] $StartPort
    [Int] $EndPort

    [Hashtable] GetRequest() {
        return @{
            start_port = $this.StartPort
            end_port   = $this.EndPort
        }
    }

    PortRange([Int] $StartPort, [Int] $EndPort) {
        $this.StartPort = $StartPort
        $this.EndPort = $EndPort
    }

    static [PortRange] new_Full() {
        return [PortRange]::new(0, 65535)
    }
}
