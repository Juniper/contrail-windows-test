. $PSScriptRoot\Result.ps1

Describe "PesterHelpers Result classes" -Tags CISelfcheck, Unit {
    Context 'SingleResult' {
        It 'is false by default' {
            $Result = [SingleResult]::new()
            ($Result.HadSucceeded()) | Should -BeFalse
        }

        It 'returns correct value' {
            $Result = [SingleResult]::new()
            $Result.Success = $false
            ($Result.HadSucceeded()) | Should -BeFalse
            $Result.Success = $true
            ($Result.HadSucceeded()) | Should -BeTrue
        }

        It 'perform or operation correctly' {
            $Result = [SingleResult]::new()
            $Result.OrSuccess($false)
            ($Result.HadSucceeded()) | Should -BeFalse
            $Result.OrSuccess($true)
            ($Result.HadSucceeded()) | Should -BeTrue
            $Result.OrSuccess($true)
            ($Result.HadSucceeded()) | Should -BeTrue
            $Result.OrSuccess($false)
            ($Result.HadSucceeded()) | Should -BeTrue
        }
    }

    Context 'MultiResult' {
        BeforeAll {
            $TrueResult = [SingleResult]::new()
            $TrueResult.Success = $true
            $FalseResult = [SingleResult]::new()
            $FalseResult.Success = $false
        }

        It 'gets null if no object in collection' {
            $Result = [MultiResult]::new()

            $Result.Get('abc') | Should -Be $null
            $Result.Add('abc', $TrueResult)
            $Result.Get('abc') | Should -Not -Be $null
            $Result.Get('abcd') | Should -Be $null
        }

        It 'gets correct object from collection' {
            $Result = [MultiResult]::new()

            $Result.Add('abc', $FalseResult)
            $Result.Add('abcd', $TrueResult)
            $Result.Get('abc') | Should -Be $FalseResult
            $Result.Get('abcd') | Should -Be $TrueResult
        }

        It 'returns added object' {
            $Result = [MultiResult]::new()

            $Result.Add('abc', $FalseResult) | Should -Be $FalseResult
            $Result.Add('abcd', $TrueResult) | Should -Be $TrueResult
        }

        It 'throws exception when trying to overwrite a value' {
            $Result = [MultiResult]::new()

            $Result.Add('abc', $FalseResult)
            { $Result.Add('abc', $TrueResult) } | Should -Throw 'This result already exists in subresults'
        }

        It 'returns fail if empty' {
            [MultiResult]::new().HadSucceeded() | Should -BeFalse
        }

        It 'returns true if all subresults are true' {
            $Result = [MultiResult]::new()

            $Result.Add('abc1', $TrueResult)
            $Result.Add('abc2', $TrueResult)

            $Result.HadSucceeded() | Should -BeTrue
        }

        It 'returns true if any subresult is false' {
            $Result = [MultiResult]::new()

            $Result.Add('abc1', $TrueResult)
            $Result.Add('abc2', $TrueResult)
            $Result.Add('abc3', $FalseResult)

            $Result.HadSucceeded() | Should -BeFalse
        }
    }
}
