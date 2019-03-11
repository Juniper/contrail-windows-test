class FirewallDirection {
    [String] $Direction

    [String] GetRequest() {
        return $this.Direction
    }
}

class BiFirewallDirection : FirewallDirection {
    BiFirewallDirection() {
        $this.Direction = '<>'
    }
}
