. $PSScriptRoot\..\..\PesterLogger\PesterLogger.ps1
. $PSScriptRoot\..\..\Utils\PowershellTools\Invoke-UntilSucceeds.ps1

function Assert-IsUDPPortListening {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session,
        [Parameter(Mandatory=$true)] [String] $ContainerName,
        [Parameter(Mandatory=$true)] [Int16] $PortNumber,
        [Parameter(Mandatory=$false)] [Int16] $MaxNetstatInvocationCount = 100,
        [Parameter(Mandatory=$false)] [Int16] $Timeout = 600
    )

    # The do-while loop is workaround for slow listener port start,
    # Check bug #1803571 for more details
    $AssertCommand = ( `
    '$NetstatInvocationCount = 0;' + `
    '$IsListenerPortOpenRegex = \"UDP.*?{0}\";' + `
    'do {{' + `
    '    if ({1} -eq $NetstatInvocationCount++) {{' + `
    '       throw \"Port on {2} container is not listening!!!\";' + `
    '   }}' + `
    '   Start-Sleep -Seconds 1;' + `
    '}} while (-not (netstat -ano | Select-String -Pattern $IsListenerPortOpenRegex));') -f $PortNumber, $MaxNetstatInvocationCount, $ContainerName

    Write-Log "Polling for port $PortNumber on container $ContainerName"
    Invoke-UntilSucceeds -Duration $Timeout -AssumeTrue {
        Invoke-Command -Session $Session -ScriptBlock {
            docker exec $Using:ContainerName powershell "$Using:AssertCommand"
        }
    } | Out-Null
}
function Send-UDPFromContainer {
    Param (
        [Parameter(Mandatory=$true)] [PSSessionT] $Session,
        [Parameter(Mandatory=$true)] [String] $ContainerName,
        [Parameter(Mandatory=$true)] [String] $Message,
        [Parameter(Mandatory=$true)] [String] $ListenerIP,
        [Parameter(Mandatory=$true)] [Int16] $ListenerPort,
        [Parameter(Mandatory=$true)] [Int16] $NumberOfAttempts,
        [Parameter(Mandatory=$true)] [Int16] $WaitSeconds
    )

    $UDPSendCommand = ( `
    '$EchoServerAddress = [System.Net.IPEndPoint]::new([IPAddress]::Parse(\"{0}\"), {1});' + `
    '$UDPSenderSocket = [System.Net.Sockets.UdpClient]::new();' + `
    '$Payload = [Text.Encoding]::UTF8.GetBytes(\"{2}\");' + `
    '1..{3} | ForEach-Object {{' + `
    '    $UDPSenderSocket.Send($Payload, $Payload.Length, $EchoServerAddress);' + `
    '    Start-Sleep -Seconds {4};' + `
    '}}') -f $ListenerIP, $ListenerPort, $Message, $NumberOfAttempts, $WaitSeconds

    $Output = Invoke-Command -Session $Session -ScriptBlock {
        docker exec $Using:ContainerName powershell "$Using:UDPSendCommand"
    }
    $Output = $Output -join [Environment]::Newline
    Write-Log "Send UDP output from remote session:"
    Write-Log -NoTimestamp -NoTag "$Output"
}
