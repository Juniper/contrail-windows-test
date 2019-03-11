class Project : BaseResourceModel {
    [FqName] $ParentFqName = [FqName]::new('default-domain')

    [String] $ResourceName = 'project'
    [String] $ParentType = 'domain'

    Project([String] $Name) {
        $this.Name = $Name

        $this.Dependencies += [Dependency]::new('security-group', 'security_groups')
    }

    [Hashtable] GetRequest() {
        return @{
            'project' = @{}
        }
    }
}
