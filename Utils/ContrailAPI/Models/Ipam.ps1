class IPAM : BaseResourceModel {
    [String] $Name = "default-network-ipam"
    [FqName] $ParentFqName = [FqName]::new(@('default-domain', 'default-project'))
    [IPAMDNSSettings] $DNSSettings = [NoneDNSSettings]::New()

    [String] $ResourceName = 'network-ipam'
    [String] $ParentType = 'project'

    [Hashtable] GetRequest() {
        $Request = @{
            "network-ipam" = @{
                "network_ipam_mgmt" = @{"ipam_dns_method" = $this.DNSSettings.DNSMode }
                "virtual_DNS_refs"  = @()
            }
        }

        if ($this.DNSSettings.DNSMode -ceq 'tenant-dns-server') {
            $this.AddTenantDNSInformation($Request)
        }
        elseif ($this.DNSSettings.DNSMode -ceq 'virtual-dns-server') {
            $this.AddVirtualDNSInformation($Request)
        }

        return $Request
    }

    hidden [Void] AddTenantDNSInformation ($Request) {
        $DNSServer = @{
            "ipam_dns_server" = @{
                "tenant_dns_server_address" = @{
                    "ip_address" = $this.DNSSettings.ServersIPs
                }
            }
        }

        $Request."network-ipam"."network_ipam_mgmt" += $DNSServer
    }

    hidden [Void] AddVirtualDNSInformation ($Request) {
        $DNSServer = @{
            "ipam_dns_server" = @{
                "virtual_dns_server_name" = $this.DNSSettings.FqServerName.ToString()
            }
        }
        $Request."network-ipam"."network_ipam_mgmt" += $DNSServer

        $VirtualServerRef = @{
            "to" = $this.DNSSettings.FqServerName.ToStringArray()
        }

        $Request."network-ipam"."virtual_DNS_refs" = @($VirtualServerRef)
    }
}

class IPAMDNSSettings {
    [String] $DNSMode
}

class NoneDNSSettings : IPAMDNSSettings {
    NoneDNSSettings() {
        $this.DNSMode = "none"
    }
}

class DefaultDNSSettings : IPAMDNSSettings {
    DefaultDNSSettings() {
        $this.DNSMode = "default-dns-server"
    }
}

class TenantDNSSettings : IPAMDNSSettings {
    [String[]] $ServersIPs
    TenantDNSSettings([String[]] $ServersIPs) {
        if (-not $ServersIPs) {
            Throw "You need to specify DNS servers"
        }
        $this.ServersIPs = $ServersIPs
        $this.DNSMode = "tenant-dns-server"
    }
}

class VirtualDNSSettings : IPAMDNSSettings {
    [FqName] $FqServerName
    VirtualDNSSettings([FqName] $FqServerName) {
        if (-not $FqServerName) {
            Throw "You need to specify DNS server"
        }
        $this.FqServerName = $FqServerName
        $this.DNSMode = "virtual-dns-server"
    }
}
