# Those are just informative to show dependencies
#include "DNSRecord.ps1"

class DNSServer : BaseResourceModel {
    [String] $Name
    [String] $DomainName = "default-domain"
    [Boolean] $DynamicRecordsFromClient = $true
    [Int] $DefaultTTLInSeconds = 86400
    [Boolean] $ExternalVisible = $false
    [Boolean] $ReverseResolution = $false
    [String] $NextDNSServer = $null
    [ValidateSet("fixed", "random", "round-robin")]
    [String] $RecordOrder = "random"
    [ValidateSet("dashed-ip", "dashed-ip-tenant-name", "vm-name", "vm-name-tenant-name")]
    [String] $FloatingIpRecord = "dashed-ip-tenant-name"

    [String] $ResourceName = 'virtual-DNS'
    [String] $ParentType = 'domain'

    DNSServer([String] $Name) {
        $this.Name = $Name
        $this.Dependencies += [Dependency]::new('virtual-DNS-record', 'virtual_DNS_records')
    }

    [FqName] GetFqName() {
        return [FqName]::New(@($this.DomainName, $this.Name))
    }

    [Hashtable] GetRequest() {
        $VirtualDNS = @{
            domain_name                 = $this.DomainName
            dynamic_records_from_client = $this.DynamicRecordsFromClient
            record_order                = $this.RecordOrder
            default_ttl_seconds         = $this.DefaultTTLInSeconds
            floating_ip_record          = $this.FloatingIpRecord
            external_visible            = $this.ExternalVisible
            reverse_resolution          = $this.ReverseResolution
        }
        if ($this.NextDNSServer) {
            $VirtualDNS += @{
                next_virtual_DNS = $this.NextDNSServer
            }
        }

        $Request = @{
            'virtual-DNS' = @{
                virtual_DNS_data = $VirtualDNS
            }
        }

        return $Request
    }
}
