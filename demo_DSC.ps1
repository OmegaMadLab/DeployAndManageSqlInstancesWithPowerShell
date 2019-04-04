#region PowerShell DSC examples

# Get a list of DSC resources available on PowerShell Gallery
Find-DscResource
Find-Module -Includes DscResource

# Get a list of of SQL Server related DSC resources available on PowerShell Gallery
Find-DscResource -Filter SQL
Find-Module -Includes DscResource -Filter SQL

# Install or update SqlServerDsc module
if(!(Get-Module -ListAvailable | Where-Object Name -eq SqlServerDsc)) {
    Install-Module SqlServerDsc
} else {
    Update-Module SqlServerDsc
}

# List DSC cmdlets
Get-Command -noun DSC*

# SQL Server specific DSC resource
Get-DscResource -Module SqlServerDsc | Select-Object Name

Start-Process -filepath "https://github.com/PowerShell/SqlServerDsc" -WindowStyle Maximized

## Simple DSC config to install a SQL Server default instance
code .\SqlSetup\SimpleSqlInstance.ps1

# Load DSC config in memory with dot sourcing
. .\SqlSetup\SimpleSqlInstance.ps1

# Compile DSC config
SimpleSqlInstance -OutputPath .\SqlSetup\DscConfig\SimpleSqlInstance

code .\SqlSetup\DscConfig\SimpleSqlInstance\localhost.mof

# Example of DSC Configuration execution
# Remember to install DSC resources on target system!!
Invoke-Command -ComputerName SQL01 -ScriptBlock { Install-Module SqlServerDsc -Force -Confirm:$false }
Start-DscConfiguration .\SqlSetup\DscConfig\SimpleSqlInstance\SimpleSqlInstance.ps1 -Wait -Verbose -Force

# DSC configuration application demo
.\SqlSetup\Media\SimpleSqlInstanceDsc.mp4

## Simple DSC config to install a SQL Server default instance with credentials
code .\SqlSetup\SimpleSqlInstanceWithCredential.ps1

# Load and compile DSC
. .\SqlSetup\SimpleSqlInstanceWithCredential.ps1
SimpleSqlInstanceWithCredential -OutputPath .\SqlSetup\DscConfig\SimpleSqlInstanceWithCredential -ConfigurationData $configData

code .\SqlSetup\DscConfig\SimpleSqlInstanceWithCredential\localhost.mof

## Two node AlwaysOn AG configuration
code .\SqlSetup\TwoNodesAlwaysOnAvg.ps1

# Add required modules on target node - pay attention to SqlServer: if not present, SqlPs is used and it can lead to errors
Invoke-Command -ComputerName SQL02,SQL03 -ScriptBlock { Install-Module SqlServerDsc, xFailoverCluster, xSmbShare, SqlServer -Force -Confirm:$false }

# Specify domain admin credential
$creds = Get-Credential

# Load and compily DSC
. .\SqlSetup\TwoNodesAlwaysOnAvg.ps1
TwoNodesAlwaysOnAvg -ConfigurationData $ConfigurationData -ActiveDirectoryAdministratorCredential $creds -OutputPath .\SqlSetup\DscConfig\TwoNodesAlwaysOnAvg

# Invoke configuration on both nodes at the same time
Start-DscConfiguration .\SqlSetup\DscConfig\SimpleSqlInstance\SimpleSqlInstance.ps1 -Wait -Verbose -Force

# DSC configuration application demo
.\SqlSetup\Media\TwoNodeAlwaysOnAG.png

#endregion