. $PSScriptRoot\..\..\PesterLogger\PesterLogger.ps1

. $PSScriptRoot/UDPClient.ps1
. $PSScriptRoot/UDPEchoServer.ps1

function Test-Ping {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session,
        [Parameter(Mandatory=$true)] [String] $SrcContainerName,
        [Parameter(Mandatory=$true)] [String] $DstIP,
        [Parameter(Mandatory=$false)] [String] $DstContainerName = $DstIP,
        [Parameter(Mandatory=$false)] [Int] $BufferSize = 32
    )

    Write-Log "Container $SrcContainerName is pinging $DstContainerName..."
    $Res = Invoke-Command -Session $Session -ScriptBlock {
        docker exec $Using:SrcContainerName powershell `
            "ping -l $Using:BufferSize $Using:DstIP; `$LASTEXITCODE;"
    }
    $Output = $Res[0..($Res.length - 2)] -join [Environment]::Newline
    $ExitCode = $Res[-1]

    Write-Log "Ping output:"
    Write-Log -NoTimestamp -NoTag "$Output"

    if ("0" -eq $ExitCode) {
        # Ping's exit code suggests everything worked, but
        # "Destination host unreachable" also returns exit code 0,
        # therefore we parse output to make sure it actually passed.
        # We check if the last ping (out of 4) returned the time
        # it took, because "host unreachable" doesn't return the time.

        # Ping sends 4 packets. Typical output is:
        # ```
        # Pinging 10.2.2.10 with 32 bytes of data:
        # Reply from 10.2.2.10: bytes=32 time=4ms TTL=127
        # Reply from 10.2.2.10: bytes=32 time=1ms TTL=127
        # Reply from 10.2.2.10: bytes=32 time=1ms TTL=127
        # Reply from 10.2.2.10: bytes=32 time=1ms TTL=127
        # ```
        # We only check the last result (fifth line):
        $LastPingReplyLine = $Res[5]

        # We use ` *` in the regex, because in some locales, ping command puts some spaces there
        if ($LastPingReplyLine | Select-String "[0-9] *ms") {
            return 0
        }
        else {
            return 2
        }
    }
    else {
        return 1
    }
}

function Test-TCP {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session,
        [Parameter(Mandatory=$true)] [String] $SrcContainerName,
        [Parameter(Mandatory=$true)] [String] $DstIP,
        [Parameter(Mandatory=$true)] [String] $DstContainerName
    )

    Write-Log "Container $SrcContainerName is sending HTTP request to $DstContainerName..."
    $Res = Invoke-Command -Session $Session -ScriptBlock {
        docker exec $Using:SrcContainerName powershell `
            "Invoke-WebRequest -Uri http://${Using:DstIP}:8080/ -UseBasicParsing -ErrorAction Continue; `$LASTEXITCODE"
    }
    $Output = $Res[0..($Res.length - 2)] -join [Environment]::Newline
    $ExitCode = $Res[-1]

    Write-Log "Web request output:"
    Write-Log -NoTimestamp -NoTag "$Output"

    return $ExitCode
}

function Test-UDP {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $ListenerContainerSession,
        [Parameter(Mandatory=$true)] [PSSessionT] $ClientContainerSession,
        [Parameter(Mandatory=$true)] [String] $ListenerContainerName,
        [Parameter(Mandatory=$true)] [String] $ListenerContainerIP,
        [Parameter(Mandatory=$true)] [String] $ClientContainerName,
        [Parameter(Mandatory=$true)] [String] $Message,
        [Parameter(Mandatory=$false)] [Int16] $UDPServerPort = 1111,
        [Parameter(Mandatory=$false)] [Int16] $UDPClientPort = 2222
    )

    Write-Log "Starting UDP Echo server on container $ListenerContainerName ..."
    Start-UDPEchoServerInContainer `
        -Session $ListenerContainerSession `
        -ContainerName $ListenerContainerName `
        -ServerPort $UDPServerPort `
        -ClientPort $UDPClientPort

    Write-Log "Starting UDP listener on container $ClientContainerName..."
    Start-UDPListenerInContainer `
        -Session $ClientContainerSession `
        -ContainerName $ClientContainerName `
        -ListenerPort $UDPClientPort

    Assert-IsUDPPortListening `
        -Session $ListenerContainerSession `
        -ContainerName $ListenerContainerName `
        -PortNumber $UDPServerPort

    Assert-IsUDPPortListening `
        -Session $ClientContainerSession `
        -ContainerName $ClientContainerName `
        -PortNumber $UDPClientPort

    Write-Log "Sending message:"
    Write-Log -NoTimestamp -NoTag "$Message"

    Write-Log "Sending UDP packet from container $ClientContainerName..."
    Send-UDPFromContainer `
        -Session $ClientContainerSession `
        -ContainerName $ClientContainerName `
        -ListenerIP $ListenerContainerIP `
        -Message $Message `
        -ListenerPort $UDPServerPort `
        -NumberOfAttempts 10 `
        -WaitSeconds 1

    Write-Log "Fetching results from listener job..."
    $ReceivedMessage = Stop-UDPListenerInContainerAndFetchResult -Session $ClientContainerSession
    Stop-EchoServerInContainer -Session $ListenerContainerSession

    Write-Log "Received message:"
    Write-Log -NoTimestamp -NoTag "$ReceivedMessage"
    if ($ReceivedMessage -eq $Message) {
        return $true
    } else {
        return $false
    }
}
