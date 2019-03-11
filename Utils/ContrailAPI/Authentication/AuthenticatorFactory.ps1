class AuthenticatorFactory {
    static [ContrailAuthenticator] GetAuthenticator([String] $AuthMethod, [PSobject] $AuthConfig) {
        $AuthType = ("$($AuthMethod)ContrailAuthenticator" -as [Type])
        $Auth = $AuthType::NewAuthenticator($AuthConfig)
        if ($null -eq $Auth) {
            $Auth = $AuthType::new()
        }
        return $Auth
    }
}
