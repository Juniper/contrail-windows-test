# Those are just informative to show dependencies
#include "PolicyRule.ps1"

class NetworkPolicy : BaseResourceModel {
    [PolicyRule[]] $PolicyRules = @()

    [String] $ResourceName = 'network-policy'
    [String] $ParentType = 'project'

    NetworkPolicy([String] $Name, [String] $ProjectName) {
        $this.Name = $Name
        $this.ParentFqName = [FqName]::New(@('default-domain', $ProjectName))
    }

    static [NetworkPolicy] new_PassAll([String] $Name, [String] $ProjectName) {
        $policy = [NetworkPolicy]::new($Name, $ProjectName)
        $rule = [PolicyRule]::new()
        $rule.Direction = "<>"
        $rule.SourceAddress = [VirtualNetworkAddress]::new()
        $rule.SourcePorts = [PortRange]::new_Full()
        $rule.DestinationAddress = [VirtualNetworkAddress]::new()
        $rule.DestinationPorts = [PortRange]::new_Full()
        $rule.Sequence = [RuleSequence]::new(-1, -1)
        $rule.Action = [SimplePassRuleAction]::new()
        $policy.PolicyRules += $rule
        return $policy
    }

    [Hashtable] GetRequest() {
        $NetworkPolicyEntries = @{
            policy_rule = @()
        }

        foreach ($PolicyRule in $this.PolicyRules) {
            $NetworkPolicyEntries.policy_rule += $PolicyRule.GetRequest()
        }

        $Request = @{
            "network-policy" = @{
                name                   = $this.Name
                display_name           = $this.Name
                network_policy_entries = $NetworkPolicyEntries
            }
        }

        return $Request
    }
}
