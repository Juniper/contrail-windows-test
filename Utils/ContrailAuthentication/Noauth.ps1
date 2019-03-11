class NoauthContrailAuthenticator : ContrailAuthenticator {
    hidden [Hashtable] GenerateAuthHeaders() {
        return @{}
    }

    # Because we didn't set $ExpirationDate, this method should never be run
    # [Void] RefreshAuthentication() {}
}
