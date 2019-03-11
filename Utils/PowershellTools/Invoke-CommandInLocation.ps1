function Invoke-CommandInLocation {
    Param(
        [Parameter(Mandatory = "true")] [String] $Directory,
        [Parameter(Mandatory = "false")] [ScriptBlock] $ScriptBlock
    )

    Push-Location $Directory

    try {
        Invoke-Command $ScriptBlock
    }
    finally {
        Pop-Location
    }
}
