class FloatingIpPool : BaseResourceModel {
    [String] $ResourceName = 'floating-ip-pool'
    [String] $ParentType = 'virtual-network'

    FloatingIpPool([String] $Name, [FqName] $NetworkFqName) {
        $this.Name = $Name
        $this.ParentFqName = $NetworkFqName
    }

    [Hashtable] GetRequest() {
        return @{
            'floating-ip-pool' = @{}
        }
    }
}
