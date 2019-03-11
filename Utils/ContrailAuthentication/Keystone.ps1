class KeystoneContrailAuthenticator : ContrailAuthenticator {
    [String] $AuthToken
    [OpenStackConfig] $OpenStackConfig

    hidden KeystoneContrailAuthenticator([OpenStackConfig] $OpenStackConfig) {
        $this.OpenStackConfig = $OpenStackConfig
        $this.ExpirationDate = Get-Date
    }

    hidden [Hashtable] GenerateAuthHeaders() {
        return @{
            'X-Auth-Token' = $this.AuthToken
        }
    }

    static [KeystoneContrailAuthenticator] NewAuthenticator([OpenStackConfig] $AuthConfig) {
        return [KeystoneV2ContrailAuthenticator]::new($AuthConfig)
    }
}

class KeystoneV2ContrailAuthenticator : KeystoneContrailAuthenticator {
    KeystoneV2ContrailAuthenticator([OpenStackConfig] $OpenStackConfig) : base($OpenStackConfig) {}

    hidden [Void] RefreshAuthentication() {
        $Request = @{
            auth = @{
                tenantName          = $this.OpenStackConfig.Project
                passwordCredentials = @{
                    username = $this.OpenStackConfig.Username
                    password = $this.OpenStackConfig.Password
                }
            }
        }

        $AuthUrl = $this.OpenStackConfig.AuthUrl() + '/tokens'
        $Response = Invoke-RestMethod -Uri $AuthUrl -Method Post -ContentType 'application/json' `
            -Body (ConvertTo-Json $Request)
        $this.AuthToken = $Response.access.token.id
    }
}
