class SystemConfig {
    [string] $AdapterName
    [string] $VHostName
    [string] $MgmtAdapterName
    [string] $ForwardingExtensionName

    [string] VMSwitchName() {
        return "Layered " + $this.AdapterName
    }

    static [SystemConfig] LoadFromFile([string] $Path) {
        $Parsed = Read-TestenvFile($Path)
        return [SystemConfig] $Parsed.System
    }
}
