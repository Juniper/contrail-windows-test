class ContrailAuthenticator {
    # Authentication token should not expire
    # in amount of seconds set by this variable.
    [Int] $SecureRequestTime = 10

    # It has to be PSobject, because DateTime cannot be $null
    [PSobject] $ExpirationDate = $null

    [Hashtable] GetAuthHeaders() {
        if ($this.ExpirationDate -and (Get-Date).AddSeconds($this.SecureRequestTime) -gt $this.ExpirationDate) {
            $this.RefreshAuthentication()
        }
        return $this.GenerateAuthHeaders()
    }

    static [ContrailAuthenticator] NewAuthenticator([PSobject] $AuthConfig) {
        return $null
    }

    hidden [Hashtable] GenerateAuthHeaders() {
        throw "Method 'GenerateAuthHeaders' not implemented in $($this.GetType())"
    }

    hidden [Void] RefreshAuthentication() {
        throw "Method 'RefreshAuthentication' not implemented in $($this.GetType())"
    }
}
