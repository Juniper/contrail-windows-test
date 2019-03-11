function Invoke-PesterTests {
    Param (
        [Parameter(Mandatory = $true)] [String] $TestRootDir,
        [Parameter(Mandatory = $false)] [String] $ReportPath,
        [Parameter(Mandatory = $false)] [String[]] $IncludeTags,
        [Parameter(Mandatory = $false)] [String[]] $ExcludeTags,
        [Parameter(Mandatory = $false)] [System.Collections.Hashtable] $AdditionalParams,
        [Parameter(Mandatory = $false)] [String[]] $CodeCovFiles = @()
    )

    $PesterScript = @{
        Path=$TestRootDir;
        Parameters=$AdditionalParams;
        Arguments=@();
    }
    if ($ReportPath) {
        New-DirIfNoExists -Path $ReportPath
        $Results = Invoke-Pester -PassThru -Script $PesterScript -Tags $IncludeTags `
            -ExcludeTag $ExcludeTags -CodeCoverage $CodeCovFiles `
            -OutputFormat NUnitXml -OutputFile $ReportPath
    } else {
        $Results = Invoke-Pester -PassThru -Script $PesterScript -Tags $IncludeTags `
            -ExcludeTag $ExcludeTags -CodeCoverage $CodeCovFiles
    }

    return $Results
}

function New-DirIfNoExists {
    Param([Parameter(Mandatory = $true)] [String] $Path)
    $Dir = Split-Path -Parent $Path
    if (-not $Dir) {
        return # we're in the output directory
    }
    if (-not (Test-Path $Dir)) {
        New-Item -Type Directory $Dir | Out-Null
    }
}
