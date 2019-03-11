class ContrailRestApi {
    [Int] $CONVERT_TO_JSON_MAX_DEPTH = 100

    [String] $RestApiUrl

    [ContrailAuthenticator] $Authenticator

    ContrailRestApi([String] $RestApiUrl, [ContrailAuthenticator] $Authenticator) {
        $this.RestApiUrl = $RestApiUrl
        $this.Authenticator = $Authenticator
    }

    hidden [String] GetResourceUrl([String] $Resource, [String] $Uuid) {
        $RequestUrl = $this.RestApiUrl + '/' + $Resource

        if (-not $Uuid) {
            $RequestUrl += 's'
        }
        else {
            $RequestUrl += ('/' + $Uuid)
        }

        return $RequestUrl
    }

    hidden [PSObject] SendRequest([String] $Method, [String] $RequestUrl,
        [Hashtable] $Request) {

        # We need to escape '<>' in 'direction' field because reasons
        # http://www.azurefieldnotes.com/2017/05/02/replacefix-unicode-characters-created-by-convertto-json-in-powershell-for-arm-templates/
        $Body = (ConvertTo-Json -Depth $this.CONVERT_TO_JSON_MAX_DEPTH $Request |
                ForEach-Object { [System.Text.RegularExpressions.Regex]::Unescape($_) })
        $Headers = $this.Authenticator.GetAuthHeaders()

        $HeadersString = $Headers.GetEnumerator()  | ForEach-Object { "$($_.Name): $($_.Value)" }
        Write-Log "[Contrail][$Method]=>[$RequestUrl]"
        Write-Log -NoTimestamp -NoTag "Headers:`n$HeadersString;`nBody:`n$Body"

        $Response = Invoke-RestMethod -Uri $RequestUrl -Headers $Headers `
            -Method $Method -ContentType 'application/json' -Body $Body

        Write-Log '[Contrail]<= '
        Write-Log -NoTimestamp -NoTag "$Response"

        return $Response
    }

    hidden [PSObject] Send([String] $Method, [String] $Resource,
        [String] $Uuid, [Hashtable] $Request) {

        $RequestUrl = $this.GetResourceUrl($Resource, $Uuid)
        return $this.SendRequest($Method, $RequestUrl, $Request)
    }

    [PSObject] Get([String] $Resource, [String] $Uuid, [Hashtable] $Request) {
        return $this.Send('Get', $Resource, $Uuid, $Request)
    }

    [PSObject] Post([String] $Resource, [String] $Uuid, [Hashtable] $Request) {
        return $this.Send('Post', $Resource, $Uuid, $Request)
    }

    [PSObject] Put([String] $Resource, [String] $Uuid, [Hashtable] $Request) {
        return $this.Send('Put', $Resource, $Uuid, $Request)
    }

    [Void] Delete([String] $Resource, [String] $Uuid, [Hashtable] $Request) {
        $this.Send('Delete', $Resource, $Uuid, $Request)
    }

    [String] FqNameToUuid ([String] $Resource, [FqName] $FqName) {
        $Request = @{
            type    = $Resource
            fq_name = $FqName.ToStringArray()
        }
        $RequestUrl = $this.RestApiUrl + '/fqname-to-id'
        $Response = $this.SendRequest('Post', $RequestUrl, $Request)
        return $Response.'uuid'
    }
}
