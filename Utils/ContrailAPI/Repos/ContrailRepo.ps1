class ContrailRepo {
    [ContrailRestApi] $API

    ContrailRepo([ContrailRestApi] $API) {
        $this.API = $API
    }

    [PSobject] Add([BaseResourceModel] $Object) {
        $Request = $Object.GetRequest()
        $Request.$($Object.ResourceName) += @{
            parent_type = $Object.ParentType
            fq_name     = $Object.GetFqName().ToStringArray()
        }

        return $this.API.Post($Object.ResourceName, $null, $Request)
    }

    [PSobject] AddOrReplace([BaseResourceModel] $Object) {
        try {
            return $this.Add($Object)
        }
        catch {
            if ([System.Net.HttpStatusCode]::Conflict -ne $_.Exception.Response.StatusCode) {
                throw
            }
        }
        $this.RemoveWithDependencies($Object)
        return $this.Add($Object)
    }

    [PSobject] Set([BaseResourceModel] $Object) {
        $Uuid = $this.API.FqNameToUuid($Object.ResourceName, $Object.GetFqName())
        $Request = $Object.GetRequest()

        return $this.API.Put($Object.ResourceName, $Uuid, $Request)
    }

    [Void] RemoveWithDependencies([BaseResourceModel] $Object) {
        $this.RemoveObject($Object, $true)
    }

    [Void] Remove([BaseResourceModel] $Object) {
        $this.RemoveObject($Object, $false)
    }

    Hidden [Void] RemoveObject([BaseResourceModel] $Object, [bool] $WithDependencies) {
        Write-Log 'Removing contrail object'
        Write-Log "`ttype: '$($Object.ResourceName)'"
        Write-Log "`tfqname: '$($Object.GetFqname().ToString())'"
        if ($WithDependencies) {
            Write-Log "`twith dependencies"
        }

        $Uuid = $this.API.FqNameToUuid($Object.ResourceName, $Object.GetFqName())

        if ($WithDependencies) {
            $this.RemoveDependencies($Object, $Uuid)
        }

        $this.API.Delete($Object.ResourceName, $Uuid, $null) | Out-Null
    }

    hidden [void] RemoveDependencies([BaseResourceModel] $Object, [String] $Uuid) {
        if (-not $Object.Dependencies) {
            return
        }
        $Response = $this.API.Get($Object.ResourceName, $Uuid, $null)
        $Props = $Response.$($Object.ResourceName).PSobject.Properties.Name

        ForEach ($Dependency in $Object.Dependencies) {
            if ($Props -contains $Dependency.ReferencesField) {
                ForEach ($Child in $Response.$($Object.ResourceName).$($Dependency.ReferencesField)) {
                    $this.API.Delete($Dependency.ResourceName, $Child.'uuid', $null)
                }
            }
        }
    }
}
