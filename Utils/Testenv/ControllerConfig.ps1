class ControllerConfig {
    [string] $MgmtAddress
    [string] $CtrlAddress
    [int] $RestApiPort
    [string] $AuthMethod

    [string] RestApiUrl() {
        return "http://$( $this.MgmtAddress ):$( $this.RestApiPort )"
    }

    static [ControllerConfig] LoadFromFile([string] $Path) {
        $Parsed = Read-TestenvFile($Path)
        return [ControllerConfig] $Parsed.Controller
    }
}
