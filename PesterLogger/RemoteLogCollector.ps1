. $PSScriptRoot\..\Utils\PowershellTools\Aliases.ps1
. $PSScriptRoot\..\Utils\PowershellTools\Invoke-NativeCommand.ps1

. $PSScriptRoot\PesterLogger.ps1

class CollectedLog {
    [String] $Name
}

class ValidCollectedLog : CollectedLog {
    [String] $Name
    [String] $Tag
    [Object] $Content
}

class InvalidCollectedLog : CollectedLog {
    [Object] $Err
}

class LogSource {
    [Testbed] $Testbed

    [CollectedLog[]] GetContent() {
        throw "LogSource is an abstract class, use specific log source instead"
    }

    ClearContent() {
        throw "LogSource is an abstract class, use specific log source instead"
    }
}

class FileLogSource : LogSource {
    [String] $FilePath
    [int64] $StartLine

    FileLogSource($Testbed, $FilePath) {
        $this.Testbed = $Testbed
        $this.FilePath = $FilePath
        $this.StartLine = $this.GetLineCount()
    }

    [int64] GetLineCount() {
        $GetLineCountBody = {
            Param([Parameter(Mandatory = $true)] [string] $From)
            if (Test-Path -PathType Leaf $From) {
                return @(Get-Content $From).Count
            } else {
                return 0
            }
        }
        return Invoke-CommandRemoteOrLocal -Func $GetLineCountBody -Testbed $this.Testbed -Arguments $this.FilePath
    }

    [CollectedLog] GetContent() {
        $ContentGetterBody = {
            Param([Parameter(Mandatory = $true)] [string] $From,
                  [Parameter(Mandatory = $true)] [int64] $StartLine,
                  [Parameter(Mandatory = $true)] [int64] $LineCount)
            if (Test-Path -PathType Leaf $From) {
                $File = Get-Item $From
                $FullContent = @(Get-Content $File)
                if ($LineCount -gt $StartLine){
                    $Content = $FullContent[$StartLine..($LineCount - 1)] | Out-String
                } else {
                    $Content = ""
                }
                return @{
                    Name = $File
                    Tag = $File.BaseName
                    Content = $Content
                }

            } else {
                return @{
                    Name = $From
                    Err = "<FILE NOT FOUND>"
                }
            }
        }
        $Start = $this.StartLine
        $LineCount = $this.GetLineCount()
        $this.StartLine = $LineCount

        # We cannot create [ValidCollectedLog] and [InvalidCollectedLog] classes directly
        # in the closure, as it may be executed in remote session, so as a workaround
        # we need to fix the types afterwards.
        return Invoke-CommandRemoteOrLocal -Func $ContentGetterBody -Testbed $this.Testbed -Arguments @($this.FilePath, $Start, $LineCount) |
            ForEach-Object {
                if ($_['Err']) {
                    [InvalidCollectedLog] $_
                } else {
                    [ValidCollectedLog] $_
                }
            }
    }

    ClearContent() {
        $LogCleanerBody = {
            Param([Parameter(Mandatory = $true)] [string] $What)
            if (Test-Path -PathType Leaf $What) {
                $File = Get-Item -Path $What -ErrorAction SilentlyContinue
                try {
                    Clear-Content $File -Force
                    return $true
                }
                catch {
                    Write-Warning "$File was not cleared due to $_"
                }
            } else {
                Write-Warning "$What was not cleared, it is not a valid path to a file"
            }
            return $false
        }
        if (Invoke-CommandRemoteOrLocal -Func $LogCleanerBody -Testbed $this.Testbed -Arguments $this.FilePath){
            $this.StartLine = 0
        }
    }
}

class EventLogLogSource : LogSource {
    [String] $EventLogName
    [String] $EventLogSource
    [int64] $StartEventIdx

    EventLogLogSource($Testbed, $EventLogName, $EventLogSource) {
        $This.Testbed = $Testbed
        $this.EventLogName = $EventLogName
        $this.EventLogSource = $EventLogSource
        $this.StartEventIdx = $this.GetLatestEventIdx() + 1
    }

    [CollectedLog[]] GetContent() {
        $LogGetterBody = {
            Param([Parameter(Mandatory = $true)] [string] $LogName,
                  [Parameter(Mandatory = $true)] [string] $LogSource,
                  [Parameter(Mandatory = $true)] [int64] $StartEventIdx,
                  [Parameter(Mandatory = $true)] [int64] $EndEventIdx)

            $Name = "$LogSource - $LogName event log"

            try {
                $Content = Get-EventLog `
                    -LogName $LogName `
                    -Source $LogSource `
                    -Index ($StartEventIdx..$EndEventIdx) | `
                        # Steps below ensure that the table outputted by `Get-EventLog` doesn't
                        # trim the `Message` field. I don't think there is a better way to do it.
                        Out-String -Width 4096 | ` # Casts each Entry object to very wide string.
                                                   # It right-pads the strings.
                                                   # Then it merges all those strings into one...
                        ForEach-Object { $_.Split([Environment]::Newline) } | ` # ...so split it...
                        ForEach-Object { $_.Trim() } # ... and trim all the right-padding.
            } catch {
                return @{
                    Name = $Name
                    Err = "event log retrieval error: $($_.Exception.Message)"
                }
            }

            # Check the index range after getting content from event log, so that we get a chance
            # to catch any other exceptions thrown by Get-EventLog.
            if ($StartEventIdx -gt $EndEventIdx) {
                return @{
                    Name = $Name
                    Err = "<EMPTY>"
                }
            }

            return @{
                Name = "EventLog from $Name"
                Tag = "$Name"
                Content = $Content
            }
        }

        $Start = $this.StartEventIdx
        $End = $this.GetLatestEventIdx()
        $this.StartEventIdx = $End + 1

        return Invoke-CommandRemoteOrLocal -Func $LogGetterBody -Testbed $this.Testbed `
                -Arguments @($this.EventLogName, $this.EventLogSource, $Start, $End) |
            ForEach-Object {
                if ($_['Err']) {
                    [InvalidCollectedLog] $_
                } else {
                    [ValidCollectedLog] $_
                }
            }
    }

    ClearContent() {
        $this.StartEventIdx = $this.GetLatestEventIdx() + 1
    }

    [int64] GetLatestEventIdx() {
        $Getter = {
            Param([Parameter(Mandatory = $true)] [string] $LogName,
                  [Parameter(Mandatory = $true)] [string] $LogSource)
            try {
                return Get-EventLog -LogName $LogName -Source $LogSource -Newest 1 | Select-Object -Expand Index
            } catch {
                # Not sure why catching [System.ArgumentException] doesn't work here.
                # This may happen if we instantiate EventLogLogCollector before the corresponding EventLog exist.
                return 0
            }
        }
        return Invoke-CommandRemoteOrLocal -Func $Getter -Testbed $this.Testbed `
            -Arguments @($this.EventLogName, $this.EventLogSource)
    }
}


class ContainerLogSource : LogSource {
    [String] $Container

    [CollectedLog[]] GetContent() {
        $Command = Invoke-NativeCommand -Session $this.Testbed -CaptureOutput -AllowNonZero {
            docker logs $Using:this.Container
        }
        $Name = "$( $this.Container ) container logs"
        $Output = $Command.Output -join [Environment]::Newline

        $Log = if (0 -eq $Command.ExitCode) {
            [ValidCollectedLog] @{
                Name = $Name
                Tag = $this.Container
                Content = $Output
            }
        } else {
            [InvalidCollectedLog] @{
                Name = $Name
                Err = $Output
            }
        }
        return $Log
    }

    ClearContent() {
        # It's not possible to clear docker container logs, but it's OK because we have fresh
        # containers in each test case.
        # If we really need to cleanup though, we could use --since flag in GetContent.
    }
}

function New-ContainerLogSource {
    Param([Parameter(Mandatory = $true)] [string[]] $ContainerNames,
          [Parameter(Mandatory = $false)] [Testbed[]] $Testbeds)

    return $Testbeds | ForEach-Object {
        $Testbed = $_
        $ContainerNames | ForEach-Object {
            [ContainerLogSource] @{
                Testbed = $Testbed
                Container = $_
            }
        }
    }
}

function New-FileLogSource {
    Param([Parameter(Mandatory = $true)] [string] $Path,
          [Parameter(Mandatory = $false)] [Testbed[]] $Testbeds)

        $GetFilesPath = {
            Param([Parameter(Mandatory = $true)] [string] $Path)
            $Files = Get-ChildItem -Path $Path -File -ErrorAction SilentlyContinue
            if ($Files) {
                return $Files.FullName
            }
            return $Path
        }

        return $Testbeds | ForEach-Object {
            $Testbed = $_
            $FilePaths = @(Invoke-CommandRemoteOrLocal -Func $GetFilesPath -Testbed $Testbed -Arguments $Path)
            $FilePaths | ForEach-Object {
                [FileLogSource]::new($Testbed, $_)
            }
        }
}

function New-EventLogLogSource {
    Param([Parameter(Mandatory = $true)] [string] $EventLogName,
          [Parameter(Mandatory = $true)] [string] $EventLogSource,
          [Parameter(Mandatory = $false)] [Testbed[]] $Testbeds)

    return $Testbeds | ForEach-Object {
        [EventLogLogSource]::new($_, $EventLogName, $EventLogSource)
    }
}

function Invoke-CommandRemoteOrLocal {
    param([ScriptBlock] $Func, [Testbed] $Testbed, [Object[]] $Arguments)
    if ($Testbed) {
        Invoke-Command -Session $Testbed.GetSession() $Func -ArgumentList $Arguments
    } else {
        Invoke-Command $Func -ArgumentList $Arguments
    }
}

function Merge-Logs {
    Param([Parameter(Mandatory = $true)] [LogSource[]] $LogSources)

    Write-Log 'Merging logs'

    foreach ($LogSource in $LogSources) {
        $SourceHost = if ($LogSource.Testbed) {
            "Testbed machine $($LogSource.Testbed.GetSession().ComputerName)"
        } else {
            "localhost"
        }

        foreach ($Log in $LogSource.GetContent()) {
            if ($Log -is [ValidCollectedLog]) {
                $Tag = "$SourceHost -> $($Log.Tag)"
                Write-Log -Tag $Tag "<$($Log.Name)>"
                if ($Log.Content) {
                    Write-Log -NoTimestamp -NoTag $Log.Content
                } else {
                    Write-Log -NoTimestamp -NoTag "<EMPTY>"
                }
            } else {
                $Tag = "$SourceHost -> ERROR"
                Write-Log -Tag $Tag "Error retrieving $($Log.Name): $($Log.Err)"
            }
        }
    }
}

function Clear-Logs {
    Param([Parameter(Mandatory = $true)] [LogSource[]] $LogSources)

    Write-Log 'Clearing logs'

    foreach ($LogSource in $LogSources) {
        $LogSource.ClearContent()
    }
}
