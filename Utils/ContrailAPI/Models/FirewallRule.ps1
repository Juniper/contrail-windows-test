# Those are just informative to show dependencies
#include "RuleAction.ps1"
#include "FirewallRuleEndpoint.ps1"
#include "FirewallService.ps1"
#include "FirewallDirection.ps1"

class FirewallRule : BaseResourceModel {
    [FirewallDirection] $Direction
    [RuleAction] $Action
    [FirewallService] $Service
    [FirewallRuleEndpoint] $Endpoint1
    [FirewallRuleEndpoint] $Endpoint2

    [String] $ResourceName = 'firewall-rule'
    [String] $ParentType = 'policy-management'

    FirewallRule(
        [String] $Name,
        [FirewallDirection] $Direction,
        [RuleAction] $Action,
        [FirewallService] $Service,
        [FirewallRuleEndpoint] $Endpoint1,
        [FirewallRuleEndpoint] $Endpoint2) {
        $this.Name = $Name
        $this.ParentFqName = [FqName]::New(@('default-policy-management'))

        $this.Direction = $Direction
        $this.Action = $Action
        $this.Service = $Service
        $this.Endpoint1 = $Endpoint1
        $this.Endpoint2 = $Endpoint2
    }

    [Hashtable] GetRequest() {
        $Request = @{
            $this.ResourceName = @{
                direction   = $this.Direction.GetRequest()
                action_list = $this.Action.GetRequest()
                service     = $this.Service.GetRequest()
                endpoint_1  = $this.Endpoint1.GetRequest()
                endpoint_2  = $this.Endpoint2.GetRequest()
            }
        }

        return $Request
    }
}
