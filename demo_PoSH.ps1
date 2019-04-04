### PowerShell SQL Server management examples


#region SQL Server SMO

#  
# Loads the SQL Server Management Objects (SMO) - old school version.
# You can also load them by loading SqlServer PowerShell module
#  
  
$ErrorActionPreference = "Stop"  
  
$sqlpsreg="HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.SqlServer.Management.PowerShell.sqlps"  
  
if (Get-ChildItem $sqlpsreg -ErrorAction "SilentlyContinue")  
{  
    throw "SQL Server Provider for Windows PowerShell is not installed."  
}  
else  
{  
    $item = Get-ItemProperty $sqlpsreg  
    $sqlpsPath = [System.IO.Path]::GetDirectoryName($item.Path)  
}  
  
$assemblylist =   
"Microsoft.SqlServer.Management.Common",  
"Microsoft.SqlServer.Smo",  
"Microsoft.SqlServer.Dmf ",  
"Microsoft.SqlServer.Instapi ",  
"Microsoft.SqlServer.SqlWmiManagement ",  
"Microsoft.SqlServer.ConnectionInfo ",  
"Microsoft.SqlServer.SmoExtended ",  
"Microsoft.SqlServer.SqlTDiagM ",  
"Microsoft.SqlServer.SString ",  
"Microsoft.SqlServer.Management.RegisteredServers ",  
"Microsoft.SqlServer.Management.Sdk.Sfc ",  
"Microsoft.SqlServer.SqlEnum ",  
"Microsoft.SqlServer.RegSvrEnum ",  
"Microsoft.SqlServer.WmiEnum ",  
"Microsoft.SqlServer.ServiceBrokerEnum ",  
"Microsoft.SqlServer.ConnectionInfoExtended ",  
"Microsoft.SqlServer.Management.Collector ",  
"Microsoft.SqlServer.Management.CollectorEnum",  
"Microsoft.SqlServer.Management.Dac",  
"Microsoft.SqlServer.Management.DacEnum",  
"Microsoft.SqlServer.Management.Utility"  
  
foreach ($asm in $assemblylist)  
{  
    $asm = [Reflection.Assembly]::LoadWithPartialName($asm)  
}  
  
Push-Location  
Set-Location $sqlpsPath  
update-FormatData -prependpath SQLProvider.Format.ps1xml   
Pop-Location

# Connect to SQL instances on SQL02 and explore properties and methods
$sqlServer = New-Object Microsoft.SqlServer.Management.Smo.Server -ArgumentList 'SQL02'
$sqlServerNamed = New-Object Microsoft.SqlServer.Management.Smo.Server -ArgumentList 'SQL02\NAMED'

$sqlServer
$sqlServerNamed

# Create a new SQL login
$sqlServer.Logins

$login = [Microsoft.SqlServer.Management.Smo.login]::new($sqlServer, 'newSqlLogin')
$login.LoginType = [Microsoft.SqlServer.Management.Smo.LoginType]::SqlLogin
$login.PasswordPolicyEnforced = $false
$login.Create('$str0ngPassw0rd')

$sqlServer.Logins

#endregion

#region SQL Server PowerShell module

Install-Module SqlServer
# OR #
Update-Module SqlServer

# List available cmdlets
Get-Command -Module SqlServer

Start-Process -filepath "https://docs.microsoft.com/en-us/powershell/module/sqlserver/?view=sqlserver-ps" -WindowStyle Maximized

# Getting help on cmdlets
Get-Help Invoke-Sqlcmd
Get-Help Invoke-Sqlcmd -Examples
Get-Help Invoke-Sqlcmd -Detailed

# Add a login - just a little bit easier than SMO
Add-SqlLogin -ServerInstance "SQL02" `
    -LoginName "SqlLoginFromPoSH" `
    -LoginType SqlLogin `
    -EnforcePasswordPolicy:$false

# Using SQL Provider for PowerShell to browse objects...
cd SQLSERVER:\SQL\SQL02\DEFAULT\LOGINS

# ... interact with them in a filesystem-like style...
Rename-Item SqlLoginFromPoSH -NewName newSqlLogin2

# ... and use SMO properties and methods on them
Get-ChildItem | ForEach-Object { $_.Script() }

#endregion

#region DBATools module
# Remove SqlServer module from memory, it may cause issues with DBATools
remove-Module SqlServer

Install-Module SqlServer
# OR #
Update-Module SqlServer
Start-Process -filepath "https://dbatools.io" -WindowStyle Maximized
Start-Process -filepath "https://docs.dbatools.io/" -WindowStyle Maximized

# List available cmdlets - generic way
Get-Command -Module DbaTools

# List available cmdlets - native way
Find-DbaCommand | Out-GridView
Find-DbaCommand -Tag Backup
Find-dbaCommand -Tag AG
Find-DbaCommand -Pattern memory

# Discover SQL Server instances in various way
Find-DbaInstance -DiscoveryType Domain
Find-DbaInstance -DiscoveryType IPRange -IpAddress 192.168.100.0/24

# Pipe with other cmdlets to assess environments
Find-DbaInstance -DiscoveryType Domain | Get-DbaLogin

# Same as before, but using a list of known instances
"SQL02", "SQL02\NAMED" | Connect-DbaInstance | Get-DbaLogin | Out-GridView

# Assess configuration values from operating system
Get-DbaPrivilege

# Execute T-SQL
$query = @"  
SELECT  @@ServerName as ServerName,
        name
FROM    sys.databases
"@

Invoke-DbaQuery -sqlInstance "SQL02", "SQL02\NAMED" -Query $query

# Install community tools, like Ola Hallengren's maintenance solution - https://ola.hallengren.com/
$maintenanceDb = New-DbaDatabase -SqlInstance "SQL02" -Name "DBAMaintenance"
$backupFolder = New-DbaDirectory -SqlInstance "SQL02" -Path C:\DbaBackup
Install-DbaMaintenanceSolution -SqlInstance "SQL02" -Database $maintenanceDb.Name -BackupLocation $backupFolder.Path -CleanupTime 24 -InstallJobs

# Schedule full backup jobs
Get-DbaAgentJob -sqlInstance SQL02 -Category "Database Maintenance" | Where-Object { $_.Name -like '*backup*full*' -and $_.JobSchedules.count -eq 0 } 

Get-DbaAgentSchedule -SqlInstance "SQL02"
$schedule = New-DbaAgentSchedule -SqlInstance "SQL02" -Schedule "Daily at midnight" -FrequencyType Daily -FrequencyInterval 24 -StartTime "000000" -Force

$fullBackupJob | Set-DbaAgentJob -ScheduleId $schedule.ID

Get-DbaAgentJob -sqlInstance SQL02 -Category "Database Maintenance" | Where-Object Name -like '*backup*full*' | Select-Object Name, JobSchedules

# Availability group management
# Add a new DB to existing AG
Get-DbaAvailabilityGroup -SqlInstance "SQL02"
New-DbaDatabase -SqlInstance "SQL02" -Name "AvgDb2"

Backup-DbaDatabase -SqlInstance "SQL02" -Database "AvgDb2" -BackupDirectory "C:\SQLBackup"
Add-DbaAgDatabase -SqlInstance "SQL02" -AvailabilityGroup "DemoAG" -Database "AvgDB2" -SeedingMode Automatic

Get-DbaAgDatabase -SqlInstance "SQL02" | Out-GridView

# Add a new DB to a new AG
New-DbaDatabase -SqlInstance "SQL02" -Name "AvgDb3"
Backup-DbaDatabase -SqlInstance "SQL02" -Database "AvgDb3" -BackupDirectory "C:\SQLBackup"

New-DbaAvailabilityGroup -Primary "SQL02" -Secondary "SQL03" -Name "DemoAG2" -ClusterType Wsfc -AvailabilityMode SynchronousCommit -FailoverMode Automatic -Database "AvgDb3" -SeedingMode Automatic

# Sync logins and agent jobs between replicas
Copy-DbaLogin -Source "SQL02" -Destination "SQL03"
Copy-DbaLogin -Source "SQL02" -Destination "SQL03" -SyncOnly
Copy-DbaAgentJob -Source "SQL02" -Destination "SQL03"


#endregion
