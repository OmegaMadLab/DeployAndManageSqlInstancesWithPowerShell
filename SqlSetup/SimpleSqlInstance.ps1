Configuration SimpleSqlInstance {

    Import-DscResource -ModuleName SqlServerDsc, PSDesiredStateConfiguration
    
    Node localhost 
    {

        #region SQL Server prerequisite
        WindowsFeature 'NetFramework45'
        {
            Name   = 'NET-Framework-45-Core'
            Ensure = 'Present'
        }
        #endregion SQL Server prerequisite

        #region SQL Server setup
        SqlSetup 'InstallDefaultInstance'
        {
            InstanceName         = 'MSSQLSERVER'
            Features             = 'SQLENGINE'
            SQLCollation         = 'SQL_Latin1_General_CP1_CI_AS'
            SQLSysAdminAccounts  = 'OMEGAMADLAB\SqlAdmins'
            InstallSharedDir     = 'C:\Program Files\Microsoft SQL Server'
            InstallSharedWOWDir  = 'C:\Program Files (x86)\Microsoft SQL Server'
            InstanceDir          = 'C:\Program Files\Microsoft SQL Server'
            InstallSQLDataDir    = 'C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLSERVER\MSSQL\Data'
            SQLUserDBDir         = 'C:\SQLData'
            SQLUserDBLogDir      = 'C:\SQLLog'
            SQLTempDBDir         = 'C:\SQLData'
            SQLTempDBLogDir      = 'C:\SQLLog'
            SQLBackupDir         = 'C:\SQLBackup'
            SourcePath           = 'D:\'
            UpdateEnabled        = 'False'
            ForceReboot          = $false

            DependsOn            = '[WindowsFeature]NetFramework45'
        }

        SqlServerNetwork 'DefaultInstanceEnableTCP'
        {
            InstanceName         = 'MSSQLSERVER'
            ProtocolName         = 'Tcp'
            IsEnabled            = $true
            TCPDynamicPort       = $false
            TCPPort              = 1433
            RestartService       = $true

            DependsOn            = '[SqlSetup]InstallDefaultInstance'
        }
        
        #endregion SQL Server setup
    }
}