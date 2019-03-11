# Those are just informative to show dependencies
#include "Subnet.ps1"
#include "NetworkPolicy.ps1"
#include "Tag.ps1"

class VirtualNetwork : BaseResourceModel {
    [Subnet] $Subnet
    [FqName] $IpamFqName = [FqName]::new(@("default-domain", "default-project", "default-network-ipam"))
    [FqName[]] $NetworkPolicysFqNames = @()

    [Boolean] $IpFabricForwarding = $false
    [FqName[]] $TagsFqNames

    [String] $ResourceName = 'virtual-network'
    [String] $ParentType = 'project'

    VirtualNetwork([String] $Name, [String] $ProjectName, [Subnet] $Subnet) {
        $this.Name = $Name
        $this.ParentFqName = [FqName]::new(@('default-domain', $ProjectName))
        $this.Subnet = $Subnet

        $this.Dependencies += [Dependency]::new('instance-ip', 'instance_ip_back_refs')
        $this.Dependencies += [Dependency]::new('virtual-machine-interface', 'virtual_machine_interface_back_refs')
    }

    [void] EnableIpFabricForwarding() {
        $this.IpFabricForwarding = $true
    }

    [Hashtable] GetRequest() {

        $IpamSubnet = @{
            subnet           = @{
                ip_prefix     = $this.Subnet.IpPrefix
                ip_prefix_len = $this.Subnet.IpPrefixLen
            }
            addr_from_start  = $true
            enable_dhcp      = $this.Subnet.DHCP
            default_gateway  = $this.Subnet.DefaultGateway
            allocation_pools = @(
                @{
                    start = $this.Subnet.AllocationPoolsStart
                    end   = $this.Subnet.AllocationPoolsEnd
                }
            )
        }

        $NetworkImap = @{
            attr = @{
                ipam_subnets = @($IpamSubnet)
            }
            to   = $this.IpamFqName.ToStringArray()
        }

        $Request = @{
            'virtual-network' = @{
                network_ipam_refs = @($NetworkImap)
            }
        }

        if ($null -ne $this.TagsFqNames) {
            $Tags = $this.GetTagsReferences()
            $Request.'virtual-network'.Add('tag_refs', $Tags)
        }

        $Policys = $this.GetPolicysReferences()
        $Request.'virtual-network'.Add('network_policy_refs', $Policys)

        if ($true -eq $this.IpFabricForwarding) {
            $ProviderNetworkFqName = [FqName]::new(
                @('default-domain', 'default-project', 'ip-fabric')
            )

            $ProviderProperties = @{
                segmentation_id = 0
                physical_network = $ProviderNetworkFqName.ToString()
            }
            $Request.'virtual-network'.Add('provider_properties', $ProviderProperties)

            $VirtualNetworkRefs = @(@{
                to = $ProviderNetworkFqName.ToStringArray()
            })
            $Request.'virtual-network'.Add('virtual_network_refs', $VirtualNetworkRefs)
        }

        return $Request
    }

    [void] AddTags([FqName[]] $TagsFqNames) {
        $this.TagsFqNames = $TagsFqNames
    }

    hidden [Hashtable[]] GetTagsReferences() {
        $References = @()
        foreach ($Tag in $this.TagsFqNames) {
            $Ref = @{
                "to" = $Tag.ToStringArray()
            }
            $References += $Ref
        }

        return $References
    }

    hidden [Hashtable[]] GetPolicysReferences() {
        $References = @()
        foreach ($NetworkPolicy in $this.NetworkPolicysFqNames) {
            $Ref = @{
                "to"   = $NetworkPolicy.ToStringArray()
                "attr" = @{
                    "timer"    = $null
                    "sequence" = @{
                        "major" = 0
                        "minor" = 0
                    }
                }
            }
            $References += $Ref
        }

        return $References
    }
}
