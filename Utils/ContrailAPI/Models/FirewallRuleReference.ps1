class FirewallRuleReference {
    [FqName] $FirewallRuleFqName
    [int] $Sequence

    FirewallRuleReference([FqName] $FirewallRule, [int] $Sequence) {
        $this.FirewallRuleFqName = $FirewallRule
        $this.Sequence = $Sequence
    }

    [Hashtable] GetRequest() {
        $Request = @{
            to   = $this.FirewallRuleFqName.ToStringArray()
            attr = @{
                sequence = $this.Sequence.ToString()
            }
        }

        return $Request
    }
}
