. $PSScriptRoot\..\..\Utils\PowershellTools\Init.ps1
. $PSScriptRoot\Configs.ps1
. $PSScriptRoot\Testbed.ps1

Describe "Testenv" -Tags CISelfcheck, Unit {

    It "should throw if filepath is invalid" {
        { [OpenStackConfig]::LoadFromFile('./bad/path.yaml') } | Should -Throw
    }

    Context "Example config" {
        It "can read OpenStack credentials config from a .yaml file" {
            $OpenStack = [OpenStackConfig]::LoadFromFile($YamlPath)
            $OpenStack.Address | Should Be "1.2.3.1"
            $OpenStack.Port | Should Be "5000"
            $OpenStack.Username | Should Be "AzureDiamond"
            $OpenStack.Password | Should Be "hunter2"
            $OpenStack.Project | Should Be "admin"

            $OpenStack.AuthUrl() | Should Be "http://1.2.3.1:5000/v2.0"
        }

        It "can read controller config from a .yaml file" {
            $Controller = [ControllerConfig]::LoadFromFile($YamlPath)
            $Controller.MgmtAddress | Should Be "1.2.3.1"
            $Controller.CtrlAddress | Should Be "1.2.3.2"
            $Controller.RestApiPort | Should Be "8082"
            $Controller.AuthMethod | Should Be "noauth"
            $Controller.RestApiUrl() | Should Be "http://1.2.3.1:8082"
        }

        It "can read testbed config from a .yaml file" {
            $System = [SystemConfig]::LoadFromFile($YamlPath)
            $System.ForwardingExtensionName | Should Be "MyExtension"
        }

        # Testbed constructor is connecting to machine to check for it's Windows Version,
        # so this test is pending.
        It "can read locations and credentials of testbeds from .yaml file" -Pending {
            $Testbeds = [Testbed]::LoadFromFile($YamlPath)
            $Testbeds[0].Address | Should Be "1.2.3.2"
            $Testbeds[1].Address | Should Be "1.2.3.3"
            $Testbeds[0].Username | Should Be "TBUsername"
            $Testbeds[1].Username | Should Be "TBUsername"
            $Testbeds[0].Password | Should Be "TBPassword"
            $Testbeds[1].Password | Should Be "TBPassword"
            $Testbeds[0].MgmtAdapterName | Should Be "Ethernet0"
            $Testbeds[1].MgmtAdapterName | Should Be "Ethernet02"
            $Testbeds[0].DataAdapterName | Should Be "Ethernet1"
            $Testbeds[1].DataAdapterName | Should Be "Ethernet12"
        }

        BeforeEach {
            $Yaml = @"
openStack:
  username: AzureDiamond
  password: hunter2
  project: admin
  address: 1.2.3.1
  port: 5000

controller:
  mgmtAddress: 1.2.3.1
  ctrlAddress: 1.2.3.2
  restApiPort: 8082
  authMethod: noauth

system:
  ForwardingExtensionName: MyExtension

testbeds:
  - name: Testbed1
    address: 1.2.3.2
    username: TBUsername
    password: TBPassword
    mgmtAdapterName: Ethernet0
    dataAdapterName: Ethernet1
  - name: Testbed2
    address: 1.2.3.3
    username: TBUsername
    password: TBPassword
    mgmtAdapterName: Ethernet02
    dataAdapterName: Ethernet12
"@
            $YamlPath = "TestDrive:\TestYaml.yaml"
            $Yaml | Out-File $YamlPath
        }
    }

    Context "Single Testbed" {
        BeforeEach {
            $Yaml = @"
testbeds:
  - name: Testbed1
    address: 1.2.3.2
    username: TBUsername
    password: TBPassword
    mgmtAdapterName: Ethernet0
    dataAdapterName: Ethernet1
"@
            $YamlPath = "TestDrive:\TestYamlSingleTestbed.yaml"
            $Yaml | Out-File $YamlPath
        }

        # Testbed constructor is connecting to machine to check for it's Windows Version,
        # so this test is pending.
        It "can read a config file with a single testbed" -Pending {
            $Testbeds = [Testbed]::LoadFromFile($YamlPath)

            $Testbeds.Count | Should Be 1
            $Testbeds[0].Name | Should Be "Testbed1"
        }
    }
}
