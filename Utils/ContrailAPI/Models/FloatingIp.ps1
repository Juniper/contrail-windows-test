class FloatingIp : BaseResourceModel {
    [String] $Address
    [FqName[]] $PortFqNames

    [String] $ResourceName = 'floating-ip'
    [String] $ParentType = 'floating-ip-pool'

    FloatingIp([String] $Name, [FqName] $PoolFqName, [String] $Address) {
        $this.Name = $Name
        $this.ParentFqName = $PoolFqName
        $this.Address = $Address
    }

    [Hashtable] GetRequest() {
        $Request = @{
            'floating-ip' = @{
                floating_ip_address = $this.Address
            }
        }
        $Ports = $this.GetPortsReferences()
        if ($Ports) {
            $Request.'floating-ip'.Add('virtual_machine_interface_refs', $Ports)
        }

        return $Request
    }

    hidden [Hashtable[]] GetPortsReferences() {
        $References = @()
        if ($this.PortFqNames) {
            foreach ($PortFqName in $this.PortFqNames) {
                $Ref = @{
                    "to" = $PortFqName.ToStringArray()
                }
                $References += $Ref
            }
        }
        return $References
    }
}
