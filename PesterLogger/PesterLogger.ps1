. $PSScriptRoot\..\Utils\PowershellTools\Aliases.ps1

# [Shelly-Bug] Shelly doesn't detect `Get-Item function:Function` as usage
. $PSScriptRoot\Get-CurrentPesterScope.ps1 # shelly: allow unused-imports

class UnsupportedPesterTestNameException : System.Exception {
    UnsupportedPesterTestNameException([string] $msg) : base($msg) {}
    UnsupportedPesterTestNameException([string] $msg, [System.Exception] $inner) : base($msg, $inner) {}
}

function Initialize-PesterLogger {
    Param([Parameter(Mandatory = $true)] [string] $Outdir)

    # Closures don't capture functions, so we need to capture them as variables.
    $WriterFunc = Get-Item function:Write-LogToFile
    $DeducerFunc = Get-Item function:Get-CurrentPesterScope

    if (-not (Test-Path $Outdir)) {
        New-Item -Force -Path $Outdir -Type Directory | Out-Null
    }
    # This is so we can change location in our test cases but it won't affect location of logs.
    $ConstOutdir = Resolve-Path $Outdir

    $WriteLogFunc = {
        Param(
            [Parameter(Mandatory=$false)] [Switch] $NoTimestamps,
            [Parameter(Mandatory=$false)] [Switch] $NoTag,
            [Parameter(Mandatory=$false)] [string] $Tag = "test-runner",
            [Parameter(Position=0,Mandatory=$true)][AllowNull()] [object] $Message
        )

        $Scope = & $DeducerFunc
        $Filename = ($Scope -join ".") + ".txt"
        if (-1 -ne ($Filename.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()))) {
            throw [UnsupportedPesterTestNameException] "Invalid test name; it cannot contain some special characters, like ':', '/', etc."
        }
        $Outpath = Join-Path $Script:ConstOutdir $Filename
        & $WriterFunc -Path $Outpath -Value $Message -Tag $Tag -NoTimestamps $NoTimestamps -NoTag $NoTag
    }.GetNewClosure()

    Register-NewFunc -Name "Write-LogImpl" -Func $WriteLogFunc
}

function Write-LogToFile {
    Param(
        [Parameter(Mandatory=$true)] [string] $Path,
        [Parameter(Mandatory=$true)][AllowNull()] [object] $Value,
        [Parameter(Mandatory=$false)] [string] $Tag,
        [Parameter(Mandatory=$true)] [bool] $NoTimestamps,
        [Parameter(Mandatory=$true)] [bool] $NoTag
    )

    if (-not $Value) {
        $Value = "<EMPTY>"
    }

    $TimestampFormatString = 'yyyy-MM-dd HH:mm:ss.ffffff'

    $Prefix = if (-not ($NoTimestamps)) {
        Get-Date -Format $TimestampFormatString
    } else {
        " " * $TimestampFormatString.Length
    }
    $Prefix += if (-not ($NoTag)) {
        " | $Tag | "
    } else {
        "        | "
    }

    $SplitValue = $Value | ForEach-Object {
        if ($_ -is [string]) {
            $_.Split([Environment]::Newline, [StringSplitOptions]::RemoveEmptyEntries)
        } else {
            # Trim, because Out-String sometimes adds whitespace for some reason
            ($_ | Out-String).Trim()
        }
    }

    $PrefixedValue = $SplitValue | ForEach-Object {
        $Prefix + $_
    }

    Add-ContentForce -Path $Path -Value $PrefixedValue | Out-Null
}

function Add-ContentForce {
    Param(
        [Parameter(Mandatory=$true)] [string] $Path,
        [Parameter(Mandatory=$true)] [object] $Value
    )

    if (-not (Test-Path $Path)) {
        New-Item -Force -Path $Path -Type File | Out-Null
    }

    Add-Content -Path $Path -Value $Value | Out-Null
}

function Register-NewFunc {
    Param([Parameter(Mandatory = $true)] [string] $Name,
          [Parameter(Mandatory = $true)] [ScriptBlock] $Func)
    if (Get-Item function:$Name -ErrorAction SilentlyContinue) {
        Remove-Item function:$Name
    }
    New-Item -Path function:\ -Name Global:$Name -Value $Func | Out-Null
}

function Write-Log {
    if (Get-Item function:Write-LogImpl -ErrorAction SilentlyContinue) {
        # This function is injected into scope by Initialize-PesterLogger
        Write-LogImpl @Args # Analyzer: Allow unknown-functions(Write-LogImpl)
    } else {
        Write-Host @Args
    }
}

class LogItem {
    [String] $Timestamp
    [String] $Tag
    [String] $Message
}

function ConvertTo-LogItem {
    Param([Parameter(ValueFromPipeline, Mandatory=$true)] $Line)

    # This function converts formatted log line back to the
    # separated components, assuming "timestamp | tag | message" format.

    Process {
        $Tag = ""
        $Timestamp = ""
        $Message = ""

        $Tuple = $Line.Split("|")
        if (2 -eq $Tuple.Length) {
            # The was one separator, e.g.
            # ```
            #                            | remote log text
            # ```
            $Message = $Tuple[1]
        } elseif (3 -eq $Tuple.Length) {
            # There were two separators, e.g.
            # ```
            # 2018-11-27 11:53:44.544036 | test-runner | foo
            # ```
            $Timestamp, $Tag, $Message = $Tuple
        }

        if ($Message.Length -gt 0) {
            # Skip first empty space in message
            $Message = $Message.Substring(1)
        }

        [LogItem] @{
            Timestamp = $Timestamp.Trim()
            Tag = $Tag.Trim()
            Message = $Message
        }
    }
}
