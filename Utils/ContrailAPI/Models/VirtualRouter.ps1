class VirtualRouter : BaseResourceModel {
    [String] $Ip
    [FqName] $ParentFqName = [FqName]::new('default-global-system-config')

    [String] $ResourceName = 'virtual-router'
    [String] $ParentType = 'global-system-config'

    VirtualRouter([String] $Name, [String] $Ip) {
        $this.Name = $Name
        $this.Ip = $Ip
    }

    [Hashtable] GetRequest() {
        return @{
            'virtual-router' = @{
                virtual_router_ip_address = $this.Ip
            }
        }
    }
}
