Dummy change to trigger Windows CI
# Running tests

This document describes how to set up everything needed for running Windows sanity tests:
* 3-node test lab (2 Windows compute nodes, 1 Linux controller),
* Windows artifacts deployed on Testbeds,
* tools to run the test suite,
* test runner scripts.

## Test lab preparation

### CodiLime lab

To deploy in local CodiLime VMWare lab, follow [this](https://juniper.github.io/contrail-windows-docs/For%20developers/Developer%20guide/Setting%20up/Devenv_in_local_env/) document.

### Juniper lab

Test lab can be provisioned easily in Juniper infra using Deploy-Dev-Env job in Windows CI Jenkins. Please refer
to [this](https://juniper.github.io/contrail-windows-docs/For%20developers/Developer%20guide/Setting%20up/Juni_lab/)
document.

### Other

There are different ways to deploy. Refer to [this](https://juniper.github.io/contrail-windows-docs/Quick_start/deployment/) document for more information.

## Deploying artifacts

### Nightly

Artifacts can be deployed from nightly build. The easiest way is to use ansible ad-hoc commands:

```
# Helper alias to run PowerShell on all testbeds
alias run_tb='ansible -i inventory --vault-password-file ~/ansible-vault-key testbed -m win_shell -a'

run_tb "mkdir C:/Artifacts"
run_tb "docker run -v C:\Artifacts:C:\Artifacts opencontrailnightly/contrail-windows-cnm-plugin"
run_tb "docker run -v C:\Artifacts:C:\Artifacts opencontrailnightly/contrail-windows-vrouter"
run_tb "Import-Certificate -CertStoreLocation Cert:\LocalMachine\Root\ C:\Artifacts\vrouter\vRouter.cer"
run_tb "Import-Certificate -CertStoreLocation Cert:\LocalMachine\TrustedPublisher\ C:\Artifacts\vrouter\vRouter.cer"
```

#### Current workarounds

*WORKAROUND*: vcpython27 is missing on testbeds:
```
run_tb "choco install vcpython27 -y"
```

*WORKAROUND*: layout of artifacts expected by test suite is slightly different than the one
created by nightly containers. We must move
```
run_tb "Copy-Item -Recurse -Filter *msi 'C:/Artifacts/*/*' 'C:/Artifacts'"
run_tb "Copy-Item -Recurse -Filter *cer 'C:/Artifacts/*/*' 'C:/Artifacts'"

# Verify that there are four MSIs (for Agent, vRouter, utils and CNM plugin) with:
run_tb "ls 'C:/Artifacts'"
```

*WORKAROUND*: when working with Debug version of vRouter Forwarding Extension, special debug DLLs
must be present on testbeds. These DLLs are:
* msvcp140d.dll
* ucrtbased.dll
* vcruntime140d.dll

MSVC 2015 debug DLLs can be obtained by installing Visual Studio 2015. After installing Visual Studio they should be located in:

mscvp140d.dll and vcruntime140d.dll - C:\Program Files (x86)\Microsoft Visual Studio 14.0\VC\redist\debug_nonredist\x64\Microsoft.VC140.DebugCRT,

ucrtbased.dll - C:\Program Files (x86)\Windows Kits\10\bin\x64\ucrt

To copy them to remote Windows testbeds, use:
```
ansible -i inventory --vault-password-file ~/ansible-vault-key testbed -m win_copy -a "dest=C:/Windows/system32/ src=/path/to/msvcp140d.dll"
ansible -i inventory --vault-password-file ~/ansible-vault-key testbed -m win_copy -a "dest=C:/Windows/system32/ src=/path/to/ucrtbased.dll"
ansible -i inventory --vault-password-file ~/ansible-vault-key testbed -m win_copy -a "dest=C:/Windows/system32/ src=/path/to/vcruntime140d.dll"
```



## Test suite prerequisites

### On test beds

1. Download python library package into correct folder:

```
New-Item -ItemType directory -Path C:\DockerFiles\python-dns -Force
pip download dnslib==0.9.7 --dest C:\DockerFiles\python-dns
```
1. Install python libraries used by tests:

```
pip install dnslib==0.9.7
pip install pathlib==1.0.1
```

### On testing machine

1. Install Pester:

    ```Install-Module -Name Pester -Force -SkipPublisherCheck -RequiredVersion 4.2.0```

1. Install `powershell-yaml`:

    ```Install-Module powershell-yaml```


## Test configuration

Copy `testenv-conf.yaml.sample` to `testenv-conf.yaml` file and replace all occurences of:
* `<CONTROLLER_IP>` - Controller IP address, accessible from local machine (network 10.84.12.0/24 in current setup)
* `<TESTBED1_NAME>`, `<TESTBED2_NAME>` - Testbeds hostnames
* `<TESTBED1_IP>`, `<TESTBED2_IP>` - Testbeds IP addresses, accessible from local machine (the same network as for Controller)


## Running the tests

Run the whole Windows sanity suite:

```
.\Invoke-ProductTests.ps1 -TestRootDir . -TestenvConfFile ..\testenv-conf.yaml -TestReportDir ../reports
```

Run selected test:

```
.\FloatingIP.Tests.ps1 -TestenvConfFile ..\testenv-conf.yaml.sample
```

### Running tests on an already deployed environment

EnvSafe tests can be run on an already deployed environment (for example by contrail-ansible-deployer). Setting PrepareEnv
flag to false will cause tests to not setup any services and become independant from deployment method:

```
Invoke-Pester -Tag 'EnvSafe' -Script @{ Path = './Tests/**/*'; Parameters = @{ PrepareEnv = $false; TestenvConfFile="testenv-conf.yaml" };}
```

### Running tests in loop

If you need to run tests in infinite loop call Set-PesterTestLoop (no parameters) at the beggining of the test script.
It is defined in `PesterHelpers\PesterHelpers.ps1`.

Whole snippet may look like this:

```
if($PSScriptRoot -match "(.*?contrail-windows-ci).*") {
    $RepositoryRootPath = $Matches[1]
}
else { throw "Cannot determine repository root path" }

. $RepositoryRootPath\Test\PesterHelpers\PesterHelpers.ps1

Suspend-PesterOnException
```

'BeforeAll' in 'Describe' block will be run once, and everything else will be looped ('AfterAll' will not be executed at all). The test will also pause on every exception thrown inside 'It' block. To resume script execution when it suspends just press enter.

If you need to finish the loop, you can write 'finish' and press enter when the script pauses or pause debbuger and set ```$global:SuspendExecutionInput = "finish"```. Current iteration of loop will finish, and 'AfterAll' block from 'Describe' will be executed.

## Debugging the tests

### Visual Studio Code

1. Install ms-vscode.powershell plugin
1. Open test file you want to debug.
1. At the top of the file, specify path to `TestenvConfFile`, like so:

```
Param (
    [Parameter(Mandatory=$false)] [string] $TestenvConfFile = "C:\Users\mk\Juniper\tmp\contrail-windows-ci\testenv-conf.yaml",
    ...
```
1. Setup any breakpoints.
1. Find the start of test suite `Describe` block.
1. Click `Debug tests` which appears just above the `Describe` block.

Note: if PowerShell session crashes, try `Ctrl`+`Shift`+`P` -> `Powershell: Restart current session`.

### Pausing tests on any exception

If you need to pause execution of tests on any exception that is thrown inside 'It' block, you can make it in two ways.

1. Add a breakpoint in pester function:

```
Set-PSBreakpoint -Script 'C:\Program Files\WindowsPowerShell\Modules\Pester\4.2.0\Functions\It.ps1' -Line 278
```

1. Call Suspend-PesterOnException (no parameters) at the beggining of the test script.
It is defined in `PesterHelpers\PesterHelpers.ps1`.
To resume script execution when it suspends just press enter.
Whole snippet may look like this:

```
if($PSScriptRoot -match "(.*?contrail-windows-ci).*") {
    $RepositoryRootPath = $Matches[1]
}
else { throw "Cannot determine repository root path" }

. $RepositoryRootPath\Test\PesterHelpers\PesterHelpers.ps1

Suspend-PesterOnException
```

## Manual cleanup of resource in Controller

When developing tests, some stray resources may appear in Contrail Controller and cause subsequent
test executions to fail (for exampe due to 409 Conflict errors).

The easiest way to clean them up is to use [contrail-api-cli](https://github.com/eonpatapon/contrail-api-cli).
It works on Windows and Linux.

Inspect the stack trace to find what resources need to be removed. For example:
```
WebException: The remote server returned an error: (409) Conflict.
at Add-ContrailPassAllPolicy, C:\Users\mk\Juniper\tmp\contrail-windows-ci\Test\Utils\ContrailAPI\NetworkPolicy.ps1: line 72
at AddPassAllPolicyOnDefaultTenant, C:\Users\mk\Juniper\tmp\contrail-windows-ci\Test\Utils\ContrailNetworkManager.ps1: line 158
at <ScriptBlock>, C:\Users\mk\Juniper\tmp\contrail-windows-ci\Test\Tests\Network\FloatingIP.Tests.ps1: line 76
at Invoke-Blocks, C:\Users\mk\Documents\WindowsPowerShell\Modules\Pester\Functions\SetupTeardown.ps1: line 140
at Invoke-TestGroupSetupBlocks, C:\Users\mk\Documents\WindowsPowerShell\Modules\Pester\Functions\SetupTeardown.ps1: line 125
at DescribeImpl, C:\Users\mk\Documents\WindowsPowerShell\Modules\Pester\Functions\Describe.ps1: line 157
```
we can see that error was thrown in NetworkPolicy.ps1, on line 72.

Here's an example of how one would remove this network-policy resource using contrail-api-cli.

```bash
# Useful alias for deployment with Keystone
alias capi='contrail-api-cli --os-username {controller:login} --os-auth-plugin v2password --os-password {controller:password} --os-auth-url http://{controller:IP}:5000/v2.0/ --os-tenant-name admin --host {controller:IP}'

# Useful alias for deployment without Keystone (noauth mode)
alias capi='contrail-api-cli --os-username {controller:login} --os-auth-plugin v2password --os-password {controller:password} --os-auth-url http://{controller:IP}:5000/v2.0/ --os-tenant-name {controller:login} --host {controller:IP}
'

capi shell # Enter interactive mode of contrail-ap-cli
```

```bash
# Example of cleanup using interactive mode
admin@10.7.0.60:/> cd network-policy
admin@10.7.0.60:/network-policy> ls
f881b652-8c1c-4009-befe-8b6e7f027865
admin@10.7.0.60:/network-policy> rm -r f881b652-8c1c-4009-befe-8b6e7f027865
This command is experimental. Use at your own risk.
About to delete:
 - f881b652-8c1c-4009-befe-8b6e7f027865
 - /virtual-network/8b0f01bf-bf71-4a79-bd9f-b6b8bf4e9c8f
'Yes' or 'No' to continue: Yes
Deleting /virtual-network/8b0f01bf-bf71-4a79-bd9f-b6b8bf4e9c8f
Delete when children still present: ['http://10.7.0.60:8082/floating-ip-pool/8ca91125-fbc8-4eb7-87fb-440513ecc048'] (HTTP 409)
admin@10.7.0.60:/network-policy> rm -r /floating-ip-pool/8ca91125-fbc8-4eb7-87fb-440513ecc048
This command is experimental. Use at your own risk.
About to delete:
 - /floating-ip-pool/8ca91125-fbc8-4eb7-87fb-440513ecc048
'Yes' or 'No' to continue: Yes
Deleting /floating-ip-pool/8ca91125-fbc8-4eb7-87fb-440513ecc048
admin@10.7.0.60:/network-policy> rm -r f881b652-8c1c-4009-befe-8b6e7f027865
This command is experimental. Use at your own risk.
About to delete:
 - f881b652-8c1c-4009-befe-8b6e7f027865
 - /virtual-network/8b0f01bf-bf71-4a79-bd9f-b6b8bf4e9c8f
'Yes' or 'No' to continue: Yes
Deleting /virtual-network/8b0f01bf-bf71-4a79-bd9f-b6b8bf4e9c8f
Deleting f881b652-8c1c-4009-befe-8b6e7f027865
admin@10.7.0.60:/network-policy> exit
```
## CI Selfcheck

To run CI Selfcheck please see [this document](../SELFCHECK.md).
