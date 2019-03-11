# Those are just informative to show dependencies
#include "PolicyRule.ps1"

class SecurityGroup : BaseResourceModel {
    [PolicyRule[]] $PolicyRules = @()

    [String] $ResourceName = 'security-group'
    [String] $ParentType = 'project'

    SecurityGroup([String] $Name, [String] $ProjectName) {
        $this.Name = $Name
        $this.ParentFqName = [FqName]::new(@('default-domain', $ProjectName))
    }

    # This method creates a default security group for a project
    # with policy rules that pass all incoming and outgoing traffic.
    static [SecurityGroup] new_Default([String] $ProjectName) {
        $group = [SecurityGroup]::new('default', $ProjectName)
        # These two, created below, policy rules
        # allow network traffic to and from security group.
        $rule1 = [PolicyRule]::new()
        $rule1.SourceAddress = [SecurityGroupAddress]::new()
        $rule1.SourcePorts = [PortRange]::new_Full()
        $rule1.DestinationAddress = [SubnetAddress]::new_Full()
        $rule1.DestinationPorts = [PortRange]::new_Full()
        $rule2 = [PolicyRule]::new()
        $rule2.SourceAddress = [SubnetAddress]::new_Full()
        $rule2.SourcePorts = [PortRange]::new_Full()
        $rule2.DestinationAddress = [SecurityGroupAddress]::new()
        $rule2.DestinationPorts = [PortRange]::new_Full()
        $group.PolicyRules += @($rule1, $rule2)
        return $group
    }

    [Hashtable] GetRequest() {
        $SecurityGroupEntries = @{
            policy_rule = @()
        }

        foreach ($PolicyRule in $this.PolicyRules) {
            $SecurityGroupEntries.'policy_rule' += $PolicyRule.GetRequest()
        }

        $Request = @{
            'security-group' = @{
                security_group_entries = $SecurityGroupEntries
            }
        }

        return $Request
    }
}
