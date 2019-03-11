Param (
    [Parameter(Mandatory=$false)] [string] $TestenvConfFile,
    [Parameter(ValueFromRemainingArguments=$true)] $UnusedParams
)

. $PSScriptRoot\DockerImageBuild.ps1
. $PSScriptRoot\Testenv\Testbed.ps1

Describe "Initialize-DockerImage" -Tags CISelfcheck, Systest {
    BeforeAll {
        $Sessions = New-RemoteSessions -VMs ([Testbed]::LoadFromFile($TestenvConfFile))
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments", "",
            Justification="Analyzer doesn't understand relation of Pester blocks"
        )]
        $Session = $Sessions[0]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            "PSUseDeclaredVarsMoreThanAssignments", "",
            Justification="Analyzer doesn't understand relation of Pester blocks"
        )]
        $DockerImageName = "python-http"
    }

    AfterAll {
        if (-not (Get-Variable Sessions -ErrorAction SilentlyContinue)) { return }
        Remove-PSSession $Sessions
    }

    It "Builds python-http image" {
        $DockerOutput = Initialize-DockerImage -Session $Session -DockerImageName $DockerImageName
        $DockerOutput | Should -Contain "Successfully tagged $( $DockerImageName ):latest"
        $DockerOutput -Join "" | Should -BeLike "*Successfully built*"

        Invoke-Command -Session $Session {
            docker inspect $Using:DockerImageName
        } | Should -Not -BeNullOrEmpty
    }
}
