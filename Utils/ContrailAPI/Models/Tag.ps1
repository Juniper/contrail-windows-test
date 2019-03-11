class Tag : BaseResourceModel {
    [String] $TypeName
    [String] $Value
    [String] $ResourceName = 'tag'
    [String] $ParentType = 'config-root'

    Tag([String] $TypeName, [String] $Value) {
        $this.Value = $Value
        $this.TypeName = $TypeName
        $this.ParentFqName = [FqName]::new(@())
    }

    [String] GetName() {
        return "$( $this.TypeName )=$( $this.Value )"
    }

    [FqName] GetFqName() {
        return [FqName]::New($this.ParentFqName, $this.GetName())
    }

    [Hashtable] GetRequest() {
        return @{
            $this.ResourceName = @{
                tag_type_name = $this.TypeName
                tag_value = $this.Value
            }
        }
    }
}
