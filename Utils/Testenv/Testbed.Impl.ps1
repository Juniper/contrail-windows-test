class Testbed {
    [string] $Name
    [string] $VMName
    [string] $Address
    [string] $Username
    [string] $Password
    [string] $MgmtAdapterName
    [string] $DataAdapterName

    [WinVersion] $WinVersion
    [String] $DefaultDockerImage
    [String] $VmSwitchName
    [String] $VHostName
    [PSSessionT] $Session = $null

    [System.Collections.Hashtable] $DataIpInfo = $null

    [PSSessionT] NewSession() {
        return $this.NewSession(10, 300000)
    }

    static [Testbed[]] LoadFromFile([string] $Path) {
        $Parsed = Read-TestenvFile($Path)
        [Testbed[]] $Testbeds = [Testbed[]]::new($Parsed.Testbeds.Count)
        foreach ($i in (0..($Parsed.Testbeds.Count-1))) {
            $Testbeds[$i] = [Testbed]::new($Parsed.Testbeds[$i])
        }
        return $Testbeds
    }

    Testbed([HashTable] $Parsed) {
        foreach($Field in $Parsed.GetEnumerator()) {
            $this.$($Field.Name) = $Field.Value
        }
        $this.SetWindowsVersion()
        $this.SetDefaultDockerImage()
        $this.SetVmSwitchName()
        $this.SetVHostName()
        $this.SetDataIpInfo()
    }

    [PSSessionT] NewSession([Int] $RetryCount, [Int] $Timeout) {
        if ($null -ne $this.Session) {
            Remove-PSSession $this.Session -ErrorAction SilentlyContinue
        }

        $Creds = $this.GetCredentials()
        $this.Session = if ($this.Address) {
            $pso = New-PSSessionOption -MaxConnectionRetryCount $RetryCount -OperationTimeout $Timeout
            New-PSSession -ComputerName $this.Address -Credential $Creds -SessionOption $pso
        }
        elseif ($this.VMName) {
            New-PSSession -VMName $this.VMName -Credential $Creds
        }
        else {
            throw "You need to specify 'address' or 'vmName' for a testbed to create a session."
        }

        $this.InitializeSession($this.Session)

        return $this.Session
    }

    [Void] RemoveAllSessions() {
        if($null -ne $this.Session) {
            Remove-PSSession $this.Session -ErrorAction Continue
            $this.Session = $null
        }
    }

    [PSSessionT] GetSession() {
        if (($null -ne $this.Session) -and ('Opened' -ne $this.Session.State)) {
            Remove-PSSession $this.Session -ErrorAction SilentlyContinue
            $this.Session = $null
        }
        if ($null -eq $this.Session) {
            return $this.NewSession()
        }
        return $this.Session
    }

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText",
        "", Justification = "This are just credentials to a testbed VM.")]
    hidden [PSCredentialT] GetCredentials() {
        if (-not ($this.Username -or $this.Password)) {
            return Get-Credential # assume interactive mode
        }
        else {
            $VMUsername = Get-UsernameInWorkgroup -Username $this.Username
            $VMPassword = $this.Password | ConvertTo-SecureString -AsPlainText -Force
            return [PSCredentialT]::new($VMUsername, $VMPassword)
        }
    }

    hidden [Void] InitializeSession([PSSessionT] $Session) {
        Invoke-Command -Session $Session -ScriptBlock {
            Set-StrictMode -Version Latest
            $ErrorActionPreference = "Stop"

            # Refresh PATH
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments",
                "", Justification = "We refresh PATH on remote machine, we don't use it here.")]
            $Env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        }
    }

    hidden [Void] SetWindowsVersion() {
        $ret = Invoke-Command -Session $this.GetSession() -ScriptBlock {
            (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').ProductName
        }
        switch -Wildcard ($ret) {
            "*2016*" {
                $this.WinVersion = [WinVersion]::v2016
            }
            "*2019*" {
                $this.WinVersion = [WinVersion]::v2019
            }
            default {
                throw 'Not supported Windows version'
            }
        }
    }

    hidden [Void] SetDefaultDockerImage() {
        switch ($this.WinVersion) {
            'v2016' {
                $this.DefaultDockerImage = 'microsoft/windowsservercore:ltsc2016'
            }
            'v2019' {
                $this.DefaultDockerImage = 'mcr.microsoft.com/windows/servercore:1809'
            }
        }
    }

    hidden [Void] SetVmSwitchName() {
        switch ($this.WinVersion) {
            'v2016' {
                $this.VmSwitchName = 'Layered ' + $this.DataAdapterName
            }
            'v2019' {
                $this.VmSwitchName = 'ContrailRootNetwork'
            }
        }
    }

    hidden [Void] SetVHostName() {
        switch ($this.WinVersion) {
            'v2016' {
                $this.VHostName = 'vEthernet (HNSTransparent)'
            }
            'v2019' {
                $this.VHostName = "vEthernet ($($this.DataAdapterName))"
            }
        }
    }

    [Void] SetDataIpInfo() {
        function Get-IpInfo {
            Param(
                [Parameter(Mandatory=$true)] [string] $adapter
            )
            Invoke-Command -Session $this.GetSession() -ScriptBlock {
                $Res = Get-NetIPAddress -ErrorAction SilentlyContinue -AddressFamily "IPv4" -InterfaceAlias $Using:adapter
                if ($null -eq $Res) {
                    return $Res
                }
                return @{
                    IPAddress = $Res.IPAddress;
                    PrefixLength = $Res.PrefixLength;
                }
            }
        }

        $this.DataIpInfo = Get-IpInfo -Adapter $this.DataAdapterName
        if ($null -eq $this.DataIpInfo) {
            $this.DataIpInfo = Get-IpInfo -Adapter $this.VHostName
        }
    }
}

class TestbedConverter : System.Management.Automation.PSTypeConverter {
    $ToTypes = @([PSSessionT])

    [Bool] CanConvertFrom([System.Object] $Source, [Type] $Destination) {
        return $false
    }
    [System.Object] ConvertFrom([System.Object] $Source, [Type] $Destination, [System.IFormatProvider] $Provider, [Bool] $IgnoreCase) {
        throw [System.InvalidCastException]::new();
    }

    [Bool] CanConvertTo([System.Object] $Source, [Type] $Destination) {
        if ($Destination -in $this.ToTypes) {
            return $true
        }
        return $false
    }
    [System.Object] ConvertTo([System.Object] $Source, [Type] $Destination, [System.IFormatProvider] $Provider, [Bool] $IgnoreCase) {
        if ($Destination.Equals([PSSessionT])) {
            return $this.ConvertToPSSession($Source)
        }
        throw [System.InvalidCastException]::new('Not implemented')
    }

    [PSSessionT] ConvertToPSSession([Testbed] $Testbed) {
        return $Testbed.GetSession()
    }
}

Update-TypeData -TypeName 'Testbed' -TypeConverter 'TestbedConverter' -ErrorAction SilentlyContinue

function New-RemoteSessions {
    Param ([Parameter(Mandatory = $true)] [Testbed[]] $VMs)

    $Sessions = [System.Collections.ArrayList] @()
    try {
        foreach ($VM in $VMs) {
            $Sessions += $VM.NewSession()
        }
    }
    catch {
        Remove-PSSession $Sessions
        throw
    }
    return $Sessions
}

function Get-ComputeLogsDir { "C:/ProgramData/Contrail/var/log/contrail" }

Enum WinVersion {
    UnChecked
    v2016
    v2019
}
