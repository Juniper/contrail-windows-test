class BaseResourceModel {
    [String] $ResourceName
    [String] $ParentType
    [Dependency[]] $Dependencies = @()

    [String] $Name
    [FqName] $ParentFqName

    # Override in derivered
    hidden [Hashtable] GetRequest() {
        throw "Operations Add/Set not permited on object: $($this.GetType().Name)"
    }

    [FqName] GetFqName() {
        return [FqName]::New($this.ParentFqName, $this.Name)
    }
}

class Dependency {
    [String] $ResourceName
    [String] $ReferencesField

    Dependency([String] $ResourceName, [String] $ReferencesField) {
        $this.ResourceName = $ResourceName
        $this.ReferencesField = $ReferencesField
    }
}

class FqName {
    [String[]] $FqName

    FqName([String[]] $FqName) {
        $this.FqName = $FqName
    }

    FqName([FqName] $ParentFqName, [String] $Name) {
        $this.FqName = $ParentFqName.FqName + @($Name)
    }

    [String[]] ToStringArray() {
        return $this.FqName
    }

    [String] ToString() {
        return [String]::Join(":", $this.FqName)
    }
}
