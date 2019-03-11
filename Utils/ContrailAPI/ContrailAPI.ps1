# Common files
. $PSScriptRoot\Models\BaseResource.ps1
. $PSScriptRoot\Authentication\ContrailAuthenticator.ps1
. $PSScriptRoot\Authentication\AuthenticatorFactory.ps1
. $PSScriptRoot\ContrailRestApi.ps1
. $PSScriptRoot\Repos\ContrailRepo.ps1

# Reusable, not resource models
. $PSScriptRoot\Models\Address.ps1
. $PSScriptRoot\Models\Protocol.ps1
. $PSScriptRoot\Models\RuleAction.ps1
. $PSScriptRoot\Models\PortRange.ps1
. $PSScriptRoot\Models\PolicyRule.ps1
. $PSScriptRoot\Models\Subnet.ps1
. $PSScriptRoot\Models\FirewallRuleEndpoint.ps1
. $PSScriptRoot\Models\FirewallService.ps1
. $PSScriptRoot\Models\FirewallRuleReference.ps1
. $PSScriptRoot\Models\FirewallDirection.ps1

# Resource models
. $PSScriptRoot\Models\ApplicationPolicy.ps1
. $PSScriptRoot\Models\DNSRecord.ps1
. $PSScriptRoot\Models\DNSServer.ps1
. $PSScriptRoot\Models\FloatingIp.ps1
. $PSScriptRoot\Models\FloatingIpPool.ps1
. $PSScriptRoot\Models\GlobalVrouterConfig.ps1
. $PSScriptRoot\Models\Ipam.ps1
. $PSScriptRoot\Models\NetworkPolicy.ps1
. $PSScriptRoot\Models\Project.ps1
. $PSScriptRoot\Models\SecurityGroup.ps1
. $PSScriptRoot\Models\Tag.ps1
. $PSScriptRoot\Models\VirtualNetwork.ps1
. $PSScriptRoot\Models\VirtualRouter.ps1
. $PSScriptRoot\Models\FirewallRule.ps1
. $PSScriptRoot\Models\FirewallPolicy.ps1

# Repositories
. $PSScriptRoot\Repos\VirtualNetworkRepo.ps1
