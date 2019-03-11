. $PSScriptRoot\Init.ps1

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"

Describe "Invoke-UntilSucceeds" -Tags CISelfcheck, Unit {
    It "fails if ScriptBlock doesn't return anything" {
        { {} | Invoke-UntilSucceeds -Duration 3 } | Should Throw
    }

    It "succeeds if ScriptBlock doesn't return anything but -AssumeTrue is set" {
        { {} | Invoke-UntilSucceeds -Duration 3 -AssumeTrue } | Should Not Throw
    }

    It "fails if ScriptBlock never returns true" {
        { { return $false } | Invoke-UntilSucceeds -Duration 3 } | Should Throw
    }

    It "fails if ScriptBlock only throws all the time" {
        { { throw "abcd" } | Invoke-UntilSucceeds -Duration 3 } | Should Throw
    }

    It "fails if ScriptBlock only throws all the time and -AssumeTrue is set" {
        { { throw "abcd" } | Invoke-UntilSucceeds -Duration 3 -AssumeTrue } | Should Throw
    }

    It "succeeds if ScriptBlock is immediately true" {
        { { return $true } | Invoke-UntilSucceeds -Duration 3 } | Should Not Throw
        { return $true } | Invoke-UntilSucceeds -Duration 3 | Should Be $true
    }

    It "stops retrying immediately when HardError is thrown" {
        $Script:Counter = 0;
        { { $Script:Counter += 1; throw [HardError]::new("bad") } | Invoke-UntilSucceeds -Duration 3 } | Should Throw
        $Script:Counter | Should -Be 1
    }

    It "succeeds for other values than pure `$true" {
        { { return "abcd" } | Invoke-UntilSucceeds -Duration 3 } | Should Not Throw
        { return "abcd" } | Invoke-UntilSucceeds -Duration 3 | Should Be "abcd"
    }

    It "can be called by not using pipe operator" {
        $Ret = Invoke-UntilSucceeds { return "abcd" } -Interval 2 -Duration 4
        $Ret | Should Be "abcd"
        Invoke-UntilSucceeds { return "abcd" } -Duration 3 | Should Be "abcd"
    }

    It "succeeds if ScriptBlock is eventually true" {
        $Script:Counter = 0
        {
            {
                $Script:Counter += 1;
                return (3 -eq $Script:Counter)
            } | Invoke-UntilSucceeds -Duration 3
        } | Should Not Throw
    }

    It "keeps retrying even when exception is throw" {
        $Script:Counter = 0
        {
            {
                $Script:Counter += 1;
                if (1 -eq $Script:Counter) {
                    return $false
                } elseif (2 -eq $Script:Counter) {
                    throw "nope"
                } elseif (3 -eq $Script:Counter) {
                    return $true
                }
            } | Invoke-UntilSucceeds -Duration 3
        } | Should Not Throw
    }

    It "retries until specified timeout is reached with sleeps in between" {
        $StartDate = Get-Date
        $ExpectedAfter = ($StartDate).AddSeconds(3)
        { { return $false } | Invoke-UntilSucceeds -Interval 1 -Duration 3 } | Should Throw
        (Get-Date).Second | Should BeExactly $ExpectedAfter.Second
    }

    It "does not allow interval equal to zero" {
        { Invoke-UntilSucceeds {} -Interval 0 -Duration 3} | Should Throw
    }

    It "does not allow interval to be greater than duration" {
        { Invoke-UntilSucceeds {} -Interval 3 -Duration 2 } | Should Throw
    }

    It "runs at least one time" {
        $Script:TimeCalled = 0
        Mock Get-Date {
            if (0 -eq $Script:TimeCalled) {
                $Script:TimeCalled += 1
                return $Script:MockStartDate.AddSeconds($Script:SecondsCounter)
            } else {
                # simulate a lot of time has passed since the first call.
                return $Script:MockStartDate.AddSeconds($Script:SecondsCounter + 100)
            }
        }
        $Script:WasCalled = $false
        Invoke-UntilSucceeds {
            $Script:WasCalled = $true;
            return $true
        } -Interval 1 -Duration 1
        $Script:WasCalled | Should Be $true
    }

    It "rethrows the last exception" {
        $HasThrown = $false
        try {
            { throw "abcd" } | Invoke-UntilSucceeds -Duration 3
        } catch {
            $HasThrown = $true
            $_.Exception.GetType().FullName | Should be "CITimeoutException"
            $_.Exception.InnerException.Message | Should Be "abcd"
        }
        $HasThrown | Should Be $true
    }

    It "throws a descriptive exception in case of never getting true" {
        $HasThrown = $false
        try {
            { return $false } | Invoke-UntilSucceeds -Duration 3
        } catch {
            $HasThrown = $true
            $_.Exception.GetType().FullName | Should be "CITimeoutException"
            $_.Exception.InnerException.Message | Should BeLike "*False."
        }
        $HasThrown | Should Be $true
    }

    It "allows a long condition always to run twice" {
        $Script:Counter = 0
        $StartDate = (Get-Date)

        Invoke-UntilSucceeds {
            Start-Sleep -Seconds 20
            $Script:Counter += 1
            2 -eq $Script:Counter
        } -Duration 10 -Interval 5

        $Script:Counter | Should Be 2
        ((Get-Date) - $StartDate).TotalSeconds | Should Be 45
    }

    It "works with duration > 60" {
        $Script:Counter = 0
        $StartDate = (Get-Date)

        {
            Invoke-UntilSucceeds {
                $Script:Counter += 1
                200 -eq $Script:Counter
            } -Duration 100 -Interval 1
        } | Should Throw

        $Script:Counter | Should BeGreaterThan 99
        $Script:Counter | Should BeLessThan 200
        ((Get-Date) - $StartDate).TotalSeconds | Should BeGreaterThan 99
    }

    It "fails when nor Duration nor NumRetries is specified" {
        { Invoke-UntilSucceeds { $true } } | Should -Throw
    }

    It "fails when both Duration and NumRetries is specified" {
        { Invoke-UntilSucceeds { $true } -Duration 5 -NumRetries 5 } | Should -Throw
    }

    It "works with NumRetries mode" {
        Invoke-UntilSucceeds { $true } -NumRetries 5 | Should -Be $True
    }

    It "retries maximally NumRetries times if the flag is set" {
        $Script:Counter = 0
        { Invoke-UntilSucceeds { $Script:Counter += 1; $false } -NumRetries 5 } | Should -Throw
        $Script:Counter | Should -Be 5
    }

    BeforeEach {
        $Script:MockStartDate = Get-Date
        $Script:SecondsCounter = 0
        Mock Start-Sleep {
            Param($Seconds)
            $Script:SecondsCounter += $Seconds;
        }
        Mock Get-Date {
            return $Script:MockStartDate.AddSeconds($Script:SecondsCounter)
        }
    }
}
