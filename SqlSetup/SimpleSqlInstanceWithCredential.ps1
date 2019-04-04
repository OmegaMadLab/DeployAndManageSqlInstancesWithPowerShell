Configuration SimpleSqlInstanceWithCredential
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullorEmpty()]
        [System.Management.Automation.PSCredential]
        $SqlServiceCredential,

        [Parameter()]
        [ValidateNotNullorEmpty()]
        [System.Management.Automation.PSCredential]
        $SqlAgentServiceCredential = $SqlServiceCredential
    )

    Import-DscResource -ModuleName SqlServerDsc, PSDesiredStateConfiguration

    node localhost
    {
        #region SQL Server prerequisites
        WindowsFeature 'NetFramework45'
        {
            Name   = 'NET-Framework-45-Core'
            Ensure = 'Present'
        }
        #endregion SQL Server prerequisites

        #region SQL Server setup
        SqlSetup 'InstallDefaultInstance'
        {
            InstanceName         = 'NAMED'
            Features             = 'SQLENGINE'
            SQLCollation         = 'SQL_Latin1_General_CP1_CI_AS'
            SQLSvcAccount        = $SqlServiceCredential
            AgtSvcAccount        = $SqlAgentServiceCredential
            SQLSysAdminAccounts  = 'OMEGAMADLAB\SqlAdmins'
            InstallSharedDir     = 'C:\Program Files\Microsoft SQL Server'
            InstallSharedWOWDir  = 'C:\Program Files (x86)\Microsoft SQL Server'
            InstanceDir          = 'C:\Program Files\Microsoft SQL Server'
            InstallSQLDataDir    = 'C:\Program Files\Microsoft SQL Server\MSSQL14.NAMED\MSSQL\Data'
            SQLUserDBDir         = 'C:\Program Files\Microsoft SQL Server\MSSQL14.NAMED\MSSQL\Data'
            SQLUserDBLogDir      = 'C:\Program Files\Microsoft SQL Server\MSSQL14.NAMED\MSSQL\Data'
            SQLTempDBDir         = 'C:\Program Files\Microsoft SQL Server\MSSQL14.NAMED\MSSQL\Data'
            SQLTempDBLogDir      = 'C:\Program Files\Microsoft SQL Server\MSSQL14.NAMED\MSSQL\Data'
            SQLBackupDir         = 'C:\Program Files\Microsoft SQL Server\MSSQL14.NAMED\MSSQL\Backup'
            SourcePath           = 'D:\'
            UpdateEnabled        = 'False'
            ForceReboot          = $false

            DependsOn            = '[WindowsFeature]NetFramework45'
        }

        SqlServerNetwork 'ChangeTcpIpOnDefaultInstance'
        {
            InstanceName         = 'NAMED'
            ProtocolName         = 'Tcp'
            IsEnabled            = $true
            TCPDynamicPort       = $false
            TCPPort              = 2226
            RestartService       = $true

            DependsOn            = '[SqlSetup]InstallDefaultInstance'
        }
        #endregion Install SQL Server
    }
}

#region ConfigurationData
$configData = @{
    AllNodes = @(
        @{
            NodeName = 'localhost'
            PSDscAllowDomainUser = $true
            PSDscAllowPlainTextPassword = $true
        }
    )
}
#endregion ConfigurationData
