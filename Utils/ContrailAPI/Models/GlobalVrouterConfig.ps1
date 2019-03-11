class GlobalVrouterConfig : BaseResourceModel {
    [String] $Name = 'default-global-vrouter-config'
    [FqName] $ParentFqName = [FqName]::New('default-global-system-config')
    [String[]] $EncapsulationPriorities = @()

    [String] $ResourceName = 'global-vrouter-config'
    [String] $ParentType = 'global-system-config'

    GlobalVrouterConfig([String[]] $EncapsulationPriorities) {
        $this.EncapsulationPriorities = $EncapsulationPriorities
    }

    [Hashtable] GetRequest() {
        return @{
            'global-vrouter-config' = @{
                encapsulation_priorities = @{
                    encapsulation = $this.EncapsulationPriorities
                }
            }
        }
    }
}
