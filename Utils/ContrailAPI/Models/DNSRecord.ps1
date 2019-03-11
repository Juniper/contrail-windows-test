class DNSRecord : BaseResourceModel {
    [ValidateSet("A", "AAAA", "CNAME", "PTR", "NS", "MX")]
    [String] $Type
    [String] $HostName
    [String] $Data
    [String] $Class = "IN"
    [Int] $TTLInSeconds = 86400

    [String] $ResourceName = 'virtual-DNS-record'
    [String] $ParentType = 'virtual-DNS'

    DNSRecord([String] $Name, [FqName] $ServerFqName, [String] $HostName, [String] $Data, [String] $Type) {
        $this.Name = $Name
        $this.ParentFqName = $ServerFqName
        $this.HostName = $HostName
        $this.Data = $Data
        $this.Type = $Type
    }

    [Hashtable] GetRequest() {
        $VirtualDNSRecord = @{
            record_name        = $this.HostName
            record_type        = $this.Type
            record_class       = $this.Class
            record_data        = $this.Data
            record_ttl_seconds = $this.TTLInSeconds
        }

        $Request = @{
            'virtual-DNS-record' = @{
                virtual_DNS_record_data = $VirtualDNSRecord
            }
        }

        return $Request
    }
}
