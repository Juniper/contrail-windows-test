Import-Module Pester

. $PSScriptRoot\..\Utils\PowershellTools\Aliases.ps1
. $PSScriptRoot\..\Utils\PowershellTools\Invoke-UntilSucceeds.ps1
. $PSScriptRoot\Result.ps1

function Consistently {
    <#
    .SYNOPSIS
    Utility wrapper for Pester for making sure that the assert is consistently true.
    It works by retrying the assert every Interval seconds, up to Duration.
    .PARAMETER ScriptBlock
    ScriptBlock containing a Pester assertion.
    .PARAMETER Interval
    Interval (in seconds) between retries.
    .PARAMETER Duration
    Timeout (in seconds).
    #>
    Param (
        [Parameter(Mandatory=$true)] [ScriptBlock] $ScriptBlock,
        [Parameter(Mandatory=$false)] [int] $Interval = 1,
        [Parameter(Mandatory=$true)] [int] $Duration = 3
    )
    if ($Duration -lt $Interval) {
        throw [CITimeoutException] "Duration must be longer than interval"
    }
    if (0 -eq $Interval) {
        throw [CITimeoutException] "Interval must not be equal to zero"
    }
    $StartTime = Get-Date
    do {
        & $ScriptBlock
        Start-Sleep -s $Interval
    } while (((Get-Date) - $StartTime).Seconds -lt $Duration)
}

function Eventually {
    <#
    .SYNOPSIS
    Utility wrapper for Pester for making sure that the assert is eventually true.
    It works by retrying the assert every Interval seconds, up to Duration. If until then,
    the assert is not true, Eventually fails.

    It is guaranteed that that if Eventually had failed, there was
    at least one check performed at time T where T >= T_start + Duration
    .PARAMETER ScriptBlock
    ScriptBlock containing a Pester assertion.
    .PARAMETER Interval
    Interval (in seconds) between retries.
    .PARAMETER Duration
    Timeout (in seconds).
    #>
    Param (
        [Parameter(Mandatory=$true)] [ScriptBlock] $ScriptBlock,
        [Parameter(Mandatory=$false)] [int] $Interval = 1,
        [Parameter(Mandatory=$true)] [int] $Duration = 3
    )

    Invoke-UntilSucceeds `
            -ScriptBlock $ScriptBlock `
            -AssumeTrue `
            -Interval $Interval `
            -Duration $Duration `
            -Name "Eventually"
}

function Test-WithRetries {
    Param (
        [Parameter(Mandatory=$true, Position = 0)] [int] $MaxNumRetries,
        [Parameter(Mandatory=$true, Position = 1)] [ScriptBlock] $ScriptBlock
    )
    $NumRetry = 1
    $GoodJob = $false
    while ($NumRetry -le $MaxNumRetries -and -not $GoodJob) {
        $FailedCountBeforeRunningTests = InModuleScope Pester {
            return $Pester.FailedCount
        }
        $NumRetry += 1
        Invoke-Command $ScriptBlock
        $FailedCountAfterRunningTests = InModuleScope Pester {
            return $Pester.FailedCount
        }
        if ($FailedCountBeforeRunningTests -eq $FailedCountAfterRunningTests) {
            $GoodJob = $true
        }
    }
}

function Test-ResultsWithRetries {
    Param ([Parameter(Mandatory=$true)] [object] $Results)

    if (0 -eq $Results.Count) {
        return $true
    }

    [MultiResult] $TestsResult = [MultiResult]::new()

        ForEach ($Result in $Results) {
        [MultiResult] $Describe = $TestsResult.Get($Result.Describe)
        if ($null -eq $Describe) {
            $Describe = $TestsResult.Add($Result.Describe, [MultiResult]::new())
            }
        if ($Result.Name -eq "Error occurred in Describe block") {
            continue
        }

        [MultiResult] $Context = $Describe.Get($Result.Context)
        if ($null -eq $Context) {
            $Context = $Describe.Add($Result.Context, [MultiResult]::new())
    }
        if ($Result.Name -eq "Error occurred in Context block") {
            continue
    }

        [SingleResult] $It = $Context.Get($Result.Name)
        if ($null -eq $It) {
            $It = $Context.Add($Result.Name, [SingleResult]::new())
        }
        $It.OrSuccess('Failed' -ne $Result.Result)
    }

    return $TestsResult.HadSucceeded()
}

function Suspend-PesterOnException {
    InModuleScope Pester {

        function global:CatchedExceptionHandler {
            if("finish" -ne $script:SuspendExecutionInput) {

                $result = ConvertTo-PesterResult -Name $Name -ErrorRecord $_
                $orderedParameters = Get-OrderedParameterDictionary -ScriptBlock $ScriptBlock -Dictionary $Parameters
                $Pester.AddTestResult( $result.name, $result.Result, $null, $result.FailureMessage, $result.StackTrace, $ParameterizedSuiteName, $orderedParameters, $result.ErrorRecord )
                if ($null -ne $OutputScriptBlock) { $Pester.testresult[-1] | & $OutputScriptBlock }
                $Pester.testresult = $Pester.testresult[0..($Pester.testresult.Length-2)]

                $script:resultWasShown = $true

                Write-Host "Press any key to continue..." -ForegroundColor Red
                [console]::beep(440,1000)
                $script:SuspendExecutionInput = Read-Host
            }
        }

        # This function is based on function Invoke-Test from Pester 4.2.0
        # https://github.com/pester/Pester/blob/5a8dd6b4aba799fb5115a2a832b26fad48bf0ccc/Functions/It.ps1
        function global:InvokeTest_Changed {
            [CmdletBinding(DefaultParameterSetName = 'Normal')]
            param (
                [Parameter(Mandatory = $true)]
                [string] $Name,

                [Parameter(Mandatory = $true)]
                [ScriptBlock] $ScriptBlock,

                [scriptblock] $OutputScriptBlock,

                [System.Collections.IDictionary] $Parameters,
                [string] $ParameterizedSuiteName,

                [Parameter(ParameterSetName = 'Pending')]
                [Switch] $Pending,

                [Parameter(ParameterSetName = 'Skip')]
                [Alias('Ignore')] [Switch] $Skip
            )

            if ($null -eq $Parameters) { $Parameters = @{} }

            try {
                if ($Skip) { $Pester.AddTestResult($Name, "Skipped", $null) }
                elseif ($Pending) { $Pester.AddTestResult($Name, "Pending", $null) }
                else {
                    $errorRecord = $null
                    $script:resultWasShown = $false
                    try {
                        $pester.EnterTest()
                        Invoke-TestCaseSetupBlocks
                        do { $null = & $ScriptBlock @Parameters } until ($true)
                    }
                    catch {
                        CatchedExceptionHandler
                        $errorRecord = $_
                    }
                    finally {
                        try { Invoke-TestCaseTeardownBlocks }
                        catch {
                             CatchedExceptionHandler
                             $errorRecord = $_
                        }
                        $pester.LeaveTest()
                    }
                    if(-not $script:resultWasShown) {
                        $result = ConvertTo-PesterResult -Name $Name -ErrorRecord $errorRecord
                        $orderedParameters = Get-OrderedParameterDictionary -ScriptBlock $ScriptBlock -Dictionary $Parameters
                        $Pester.AddTestResult( $result.name, $result.Result, $null, $result.FailureMessage, $result.StackTrace, $ParameterizedSuiteName, $orderedParameters, $result.ErrorRecord )
                    }
                }
            }
            finally { Exit-MockScope -ExitTestCaseOnly }
            if(-not $script:resultWasShown) {
                if ($null -ne $OutputScriptBlock) { $Pester.testresult[-1] | & $OutputScriptBlock }
            }
        }

        New-Alias -Name 'Invoke-Test' -Value 'InvokeTest_Changed' -Scope Global -ErrorAction Ignore
    }
}

function Set-PesterTestLoop {
    Suspend-PesterOnException

    InModuleScope Pester {
        # This function is based on function DescribeImpl from Pester 4.2.0
        # https://github.com/pester/Pester/blob/5a8dd6b4aba799fb5115a2a832b26fad48bf0ccc/Functions/Describe.ps1
        function global:DescribeImpl_Changed {
            param(
                [Parameter(Mandatory = $true, Position = 0)]
                [string] $Name,
                [Alias('Tags')]
                $Tag=@(),
                [Parameter(Position = 1)]
                [ValidateNotNull()]
                [ScriptBlock] $Fixture = $(Throw "No test script block is provided. (Have you put the open curly brace on the next line?)"),
                [string] $CommandUsed = 'Describe',
                $Pester,
                [scriptblock] $DescribeOutputBlock,
                [scriptblock] $TestOutputBlock,
                [switch] $NoTestDrive
            )

            Assert-DescribeInProgress -CommandName $CommandUsed

            if (2 -eq $Pester.TestGroupStack.Count) {
                if($Pester.TestNameFilter-and -not ($Pester.TestNameFilter | & $SafeCommands['Where-Object'] { $Name -like $_ })) {
                    return
                }
                if($Pester.TagFilter -and @(& $SafeCommands['Compare-Object'] $Tag $Pester.TagFilter -IncludeEqual -ExcludeDifferent).count -eq 0) {return}
                if($Pester.ExcludeTagFilter -and @(& $SafeCommands['Compare-Object'] $Tag $Pester.ExcludeTagFilter -IncludeEqual -ExcludeDifferent).count -gt 0) {return}
            }
            else {
                if ($PSBoundParameters.ContainsKey('Tag')) {
                    Write-Warning "${CommandUsed} '$Name': Tags are only effective on the outermost test group, for now."
                }
            }

            $Pester.EnterTestGroup($Name, $CommandUsed)

            if ($null -ne $DescribeOutputBlock) {
                & $DescribeOutputBlock $Name $CommandUsed
            }

            $testDriveAdded = $false
            try {
                try {
                    if (-not $NoTestDrive) {
                        if (-not (Test-Path TestDrive:\)) {
                            New-TestDrive
                            $testDriveAdded = $true
                        }
                        else {
                            $TestDriveContent = Get-TestDriveChildItem
                        }
                    }

                    Add-SetupAndTeardown -ScriptBlock $Fixture
                    Invoke-TestGroupSetupBlocks

                    if('Describe' -eq $CommandUsed) {
                        do {
                            $null = & $Fixture
                            if("finish" -eq $script:SuspendExecutionInput) {
                                $script:SuspendExecutionInput = ""
                                break
                            }
                        } until ($false)
                    } else {
                        do { $null = & $Fixture } until ($true)
                    }
                }
                finally {
                    Invoke-TestGroupTeardownBlocks
                    if (-not $NoTestDrive) {
                        if ($testDriveAdded) {
                            Remove-TestDrive
                        }
                        else {
                            Clear-TestDrive -Exclude ($TestDriveContent | & $SafeCommands['Select-Object'] -ExpandProperty FullName)
                        }
                    }
                }
            }
            catch {
                $firstStackTraceLine = $_.InvocationInfo.PositionMessage.Trim() -split "$([System.Environment]::NewLine)" | & $SafeCommands['Select-Object'] -First 1
                $Pester.AddTestResult("Error occurred in $CommandUsed block", "Failed", $null, $_.Exception.Message, $firstStackTraceLine, $null, $null, $_)
                if ($null -ne $TestOutputBlock)  {
                    & $TestOutputBlock $Pester.TestResult[-1]
                }
            }
            Exit-MockScope
            $Pester.LeaveTestGroup($Name, $CommandUsed)
        }
        New-Alias -Name 'DescribeImpl' -Value 'DescribeImpl_Changed' -Scope Global -ErrorAction Ignore
    }
}
