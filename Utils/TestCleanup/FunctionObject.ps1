class FunctionObject {
    [ScriptBlock] $ScriptBlock
    [PSobject[]] $Arguments

    FunctionObject([ScriptBlock] $ScriptBlock, [PSobject[]] $Arguments) {
        $this.ScriptBlock = $ScriptBlock
        $this.Arguments = $Arguments
    }
}
