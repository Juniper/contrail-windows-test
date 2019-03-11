function Get-CurrentPesterScope {
    # UGLY HACK WARNING
    # -----------------
    # We use Pester's InModuleScope utility for spying on private methods/variables...
    # ... to spy on Pester itself.
    # Forgive me.
    return InModuleScope Pester {
        $AllScopes = @()
        $i = 1
        while ($true) {
            try {
                # Oh dear.
                #
                # -Scope denotes current scope.
                # 0 is active (local) scope.
                # 1 is parent scope
                # 2 is grand-parent scope, etc.
                # `Get-Help about_Scopes` for more about Numbered Scopes.
                # (we start at $i = 1, which is parent scope).
                #
                # We use SilentlyContinue, because Get-Variable sends stuff to stderr if can't 
                # find a variable with specified name.
                #
                # Pester holds current scope block name (the string after Describe, Context, It)
                # in $Name variable.
                $PesterScopeNameVariableName = "Name"
                $ScopeName = (Get-Variable -Name $PesterScopeNameVariableName -ValueOnly `
                    -Scope $i -ErrorAction SilentlyContinue)
                $AllScopes += $ScopeName
            } catch [System.Management.Automation.PSArgumentOutOfRangeException] {
                # Eventually Get-Variable starts throwing that there are no more scopes.
                break
            }
            # We jump by 2 scopes at a time, because each Pester block consists of
            # two scopes I guess
            $i += 2
        }
        [Array]::Reverse($AllScopes)
        return $AllScopes
    }
}
