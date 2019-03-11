class Result {
    [Bool] HadSucceeded() {
        throw "Virtual Method"
    }
}

class SingleResult : Result {
    [Bool] $Success = $false

    [Bool] HadSucceeded() {
        return $this.Success
    }

    [Void] OrSuccess([Bool] $NewSuccess) {
        $this.Success = ($this.Success -or $NewSuccess)
    }
}

class MultiResult : Result {
    [Hashtable] $SubResults = @{}

    [Bool] HadSucceeded() {
        return $this.AllSubsHadSucceeded()
    }

    hidden [Bool] AllSubsHadSucceeded() {
        if (0 -eq $this.SubResults.Count) {
            return $false
        }

        foreach ($Sub in $this.SubResults.Values) {
            if (-not $Sub.HadSucceeded()) {
                return $false
            }
        }

        return $true
    }

    [Result] Add([String] $ResultName, [Result] $Result) {
        if ($this.SubResults.Keys -contains $ResultName) {
            throw 'This result already exists in subresults'
        }
        $this.SubResults.Add($ResultName, $Result)
        return $Result
    }

    [Result] Get([String] $ResultName) {
        return $this.SubResults[$ResultName]
    }
}
