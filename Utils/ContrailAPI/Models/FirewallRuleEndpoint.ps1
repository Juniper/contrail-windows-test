class FirewallRuleEndpoint {}

class TagsFirewallRuleEndpoint : FirewallRuleEndpoint {
    [String[]] $Tags

    TagsFirewallRuleEndpoint([String[]] $Tags) {
        $this.Tags = $Tags
    }

    [Hashtable] GetRequest() {
        return @{ tags = $this.Tags }
    }
}
