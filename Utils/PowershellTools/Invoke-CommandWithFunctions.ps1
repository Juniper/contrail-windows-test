. $PSScriptRoot/Aliases.ps1

function Invoke-CommandWithFunctions {
    <#
    .SYNOPSIS
    This is a helper function that solves the following problem:
    PowerShell does not support passing functions to remote session,
    like ScriptBlocks or locally defined variables (by "$using:").

    What Invoke-CommandWithFunctions does is defining functions at remote
    session by using local definitions allowing to call the functions in 
    ScriptBlock without any additional syntax.
    After invocation of the ScriptBlock we remove the definitions from remote 
    session memory so we do not pollute it.
    .PARAMETER ScriptBlock
    ScriptBlock with commands invoked in the remote session.
    ScriptBlock can contain calls to functions passed in $Functions parameter.
    Refer to tests for examples.
    .PARAMETER Session
    Remote session where the Scriptblock will be invoked.
    .PARAMETER Functions
    Names of locally defined functions to be made available in remote scope.
    #>
    Param(
        [Parameter(Mandatory=$true)] [ScriptBlock] $ScriptBlock,
        [Parameter(Mandatory=$true)] [PSSessionT] $Session,
        [Parameter(Mandatory=$true)] [string[]] $Functions
    )

    $FunctionsInvoked = $Functions `
        | ForEach-Object { @{ Name = $_; Body = Get-Content function:$_ } }

    Invoke-Command -Session $Session -ScriptBlock {
        $Using:FunctionsInvoked `
            | ForEach-Object { Invoke-Expression "function $( $_.Name ) { $( $_.Body ) }" }
    }

    try {
        return Invoke-Command -Session $Session -ScriptBlock $ScriptBlock
    }
    finally {
        Invoke-Command -Session $Session -ScriptBlock {
            $Using:FunctionsInvoked `
                | ForEach-Object { Remove-Item -Path "Function:$( $_.Name )" }
        }
    }
}
