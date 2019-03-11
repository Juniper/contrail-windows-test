. $PSScriptRoot\..\..\TestConfigurationUtils.ps1

function Initialize-DockerNetworks {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session,
        [Parameter(Mandatory=$true)] [String] $TenantName,
        [Parameter(Mandatory=$true)] [VirtualNetwork[]] $Networks
    )
    foreach ($Network in $Networks) {
        $ID = New-DockerNetwork -Session $Session `
            -TenantName $TenantName `
            -Name $Network.Name `
            -Subnet "$( $Network.Subnet.IpPrefix )/$( $Network.Subnet.IpPrefixLen )"

        Write-Log "Created network id: $ID"
    }
}
