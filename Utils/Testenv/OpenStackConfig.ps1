class OpenStackConfig {
    [string] $Username
    [string] $Password
    [string] $Project
    [string] $Address
    [int] $Port

    [string] AuthUrl() {
        return "http://$( $this.Address ):$( $this.Port )/v2.0"
    }

    static [OpenStackConfig] LoadFromFile([string] $Path) {
        $Parsed = Read-TestenvFile($Path)
        if ($Parsed.keys -notcontains 'OpenStack') {
            return $null
        }
        return [OpenStackConfig] $Parsed.OpenStack
    }
}
