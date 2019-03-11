# Create PSSessionT alias
$AccelPSSessionT = [PowerShell].Assembly.GetType("System.Management.Automation.TypeAccelerators")
$AccelPSSessionT::add("PSSessionT", "System.Management.Automation.Runspaces.PSSession")

# Create PSCredentialT alias
$AccelPSCredentialT = [PowerShell].Assembly.GetType("System.Management.Automation.TypeAccelerators")
$AccelPSCredentialT::add("PSCredentialT", "System.Management.Automation.PSCredential")
