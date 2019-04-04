<#
.EXAMPLE
    In this example, we will create an AlwaysOn Availability Groups system with two replicas.
    Both replicas will host a SQL Server default instance executed by NT SERVICE\MSSQLSERVER account.
    DSc configuration executes following tasks:
    - It installs failover cluster components on both node, and forms a new cluster
    - It creates an availability group with two sync replicas and automatic failover
    - It configure a new share to host backups for AG seeding
    - It adds a new db on primary replica, and join it to availability group

    Assumptions:
    - We will assume that a Domain Controller already exists, and that both servers are already domain joined.
    - We will work in PUSH mode. The example code allow for plain text passwords and domain credential; feel free 
      to increase security upon your needs.
    - The example also assumes that the CNO (Cluster Name Object) is either prestaged or that the Active Directory
      administrator credential has the appropriate permission to create the CNO (Cluster Name Object).
    - The example doesn't configure a witness for the failover cluster; add it for use in other scenarios
#>

#region ConfigurationData
$ConfigurationData = @{
    AllNodes = @(
        @{
            NodeName                      = '*'

            # For demo purposes only! Use certificates in production!
            PSDscAllowPlainTextPassword   = $true
            PSDscAllowDomainUser          = $true
            
            ClusterName                   = 'SQLCLUSTER'
            ClusterIPAddress              = '192.168.100.110/24'

            InstanceName                  = 'MSSQLSERVER'

            ProcessOnlyOnActiveNode       = $true

            AvailabilityMode              = 'SynchronousCommit'
            BackupPriority                = 50
            ConnectionModeInPrimaryRole   = 'AllowAllConnections'
            ConnectionModeInSecondaryRole = 'AllowNoConnections'
            FailoverMode                  = 'Automatic'

            SqlBackupPath                 = "C:\SqlBackup"

            AGName                        = "DemoAG"
            
        },

        # Node01 - First cluster node.
        @{
            # Replace with the name of the actual target node.
            NodeName = 'SQL02'

            # This is used in the configuration to know which resource to compile.
            Role     = 'PrimaryReplica'

            # This is used to assign permission to instance svc account while it's operating on network resources
            ComputerAccountName  = "OMEGAMADLAB\SQL02$"
        },

        # Node02 - Second cluster node
        @{
            # Replace with the name of the actual target node.
            NodeName = 'SQL03'

            # This is used in the configuration to know which resource to compile.
            Role     = 'SecondaryReplica'

            # This is used to assign permission to instance svc account while it's operating on network resources
            ComputerAccountName  = "OMEGAMADLAB\SQL03$"
        }
    )
}
#endregion

#region DSC Configuration
Configuration TwoNodesAlwaysOnAvg
{
    param(
        [Parameter(Mandatory = $true)]
        [PSCredential]
        $ActiveDirectoryAdministratorCredential,

        [Parameter()]
        [ValidateNotNullorEmpty()]
        [System.Management.Automation.PSCredential]
        $SqlAdministratorCredential = $ActiveDirectoryAdministratorCredential

    )

    Import-DscResource -ModuleName PsDesiredStateConfiguration, xFailOverCluster, SqlServerDsc, xSmbShare, cNtfsAccessControl

    Node $AllNodes.NodeName
    {
        #region Activities executed on both nodes

        #region Failover cluster prerequisites
        WindowsFeature AddFailoverFeature
        {
            Ensure = 'Present'
            Name   = 'Failover-clustering'
        }

        WindowsFeature AddRsatCluster
        {
            Ensure                  = 'Present'
            Name                    = 'RSAT-Clustering'
            IncludeAllSubFeature    = $true
            
            DependsOn               = '[WindowsFeature]AddFailoverFeature'

        }
        #endregion

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
            SQLSysAdminAccounts  = $SqlAdministratorCredential.UserName
            InstallSharedDir     = 'C:\Program Files\Microsoft SQL Server'
            InstallSharedWOWDir  = 'C:\Program Files (x86)\Microsoft SQL Server'
            InstanceDir          = 'C:\Program Files\Microsoft SQL Server'
            InstallSQLDataDir    = 'C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLSERVER\MSSQL\Data'
            SQLUserDBDir         = 'C:\SQLData'
            SQLUserDBLogDir      = 'C:\SQLLog'
            SQLTempDBDir         = 'C:\SQLData'
            SQLTempDBLogDir      = 'C:\SQLLog'
            SQLBackupDir         = $NodeName.SqlBackupPath
            SourcePath           = 'D:\'
            UpdateEnabled        = 'False'
            ForceReboot          = $false

            DependsOn            = '[WindowsFeature]NetFramework45'
        }
        #endregion SQL Server setup

        #region SQL Server configuration

        # Adding the required service account login
        SqlServerLogin AddSystemAccountLogin
        {
            Ensure               = 'Present'
            Name                 = 'NT AUTHORITY\SYSTEM'
            LoginType            = 'WindowsUser'
            ServerName           = $Node.NodeName
            InstanceName         = $Node.InstanceName
            PsDscRunAsCredential = $SqlAdministratorCredential

            DependsOn            = '[SqlSetup]InstallDefaultInstance'
        }

        # Add the required permissions to the NT AUTHORITY\SYSTEM login
        SqlServerPermission AddSystemAccountPermissions
        {
            Ensure               = 'Present'
            ServerName           = $Node.NodeName
            InstanceName         = $Node.InstanceName
            Principal            = 'NT AUTHORITY\SYSTEM'
            Permission           = 'AlterAnyAvailabilityGroup', 'ViewServerState'
            PsDscRunAsCredential = $SqlAdministratorCredential

            DependsOn            = '[SqlServerLogin]AddSystemAccountLogin'
        }

        # Adding the CLUSSVC login
        SqlServerLogin AddClusSvcLogin
        {
            Ensure               = 'Present'
            Name                 = 'NT SERVICE\ClusSvc'
            LoginType            = 'WindowsUser'
            ServerName           = $Node.NodeName
            InstanceName         = $Node.InstanceName
            PsDscRunAsCredential = $SqlAdministratorCredential

            DependsOn            = '[SqlSetup]InstallDefaultInstance'
        }

        # Add the required permissions to ClusSvc login
        SqlServerPermission AddClusSvcPermissions
        {
            Ensure               = 'Present'
            ServerName           = $Node.NodeName
            InstanceName         = $Node.InstanceName
            Principal            = 'NT SERVICE\ClusSvc'
            Permission           = 'AlterAnyAvailabilityGroup', 'ViewServerState'
            PsDscRunAsCredential = $SqlAdministratorCredential

            DependsOn            = '[SqlServerLogin]AddClusSvcLogin'
        }

        # Adding the Computer account login
        SqlServerLogin AddComputerAccountLoginPrimaryReplica
        {
            Ensure               = 'Present'
            Name                 = ( $AllNodes | Where-Object { $_.Role -eq 'PrimaryReplica' } ).ComputerAccountName
            LoginType            = 'WindowsUser'
            ServerName           = $Node.NodeName
            InstanceName         = $Node.InstanceName
            PsDscRunAsCredential = $SqlAdministratorCredential

            DependsOn            = '[SqlSetup]InstallDefaultInstance'
        }

        SqlServerLogin AddComputerAccountLoginSecondaryReplica
        {
            Ensure               = 'Present'
            Name                 = ( $AllNodes | Where-Object { $_.Role -eq 'SecondaryReplica' } ).ComputerAccountName
            LoginType            = 'WindowsUser'
            ServerName           = $Node.NodeName
            InstanceName         = $Node.InstanceName
            PsDscRunAsCredential = $SqlAdministratorCredential

            DependsOn            = '[SqlSetup]InstallDefaultInstance'
        }

        # # Add the required permissions to computer account login
        # SqlServerPermission AddComputerAccountPermissions
        # {
        #     Ensure               = 'Present'
        #     ServerName           = $Node.NodeName
        #     InstanceName         = $Node.InstanceName
        #     Principal            = $Node.ComputerAccountName
        #     Permission           = 'AlterAnyAvailabilityGroup', 'ViewServerState'
        #     PsDscRunAsCredential = $SqlAdministratorCredential

        #     DependsOn            = '[SqlServerLogin]AddComputerAccountLogin'
        # }

        # Create a DatabaseMirroring endpoint
        SqlServerEndpoint HADREndpoint
        {
            EndPointName         = 'HADR'
            Ensure               = 'Present'
            Port                 = 5022
            ServerName           = $Node.NodeName
            InstanceName         = $Node.InstanceName
            PsDscRunAsCredential = $SqlAdministratorCredential

            DependsOn            = '[SqlSetup]InstallDefaultInstance'
        }

        SqlServerEndpointPermission SQLConfigureEndpointPermissionPrimary
        {
            Ensure               = 'Present'
            ServerName           = $Node.NodeName
            InstanceName         = $Node.InstanceName
            Name                 = 'HADR'
            Principal            = ( $AllNodes | Where-Object { $_.Role -eq 'PrimaryReplica' } ).ComputerAccountName
            Permission           = 'CONNECT'
            PsDscRunAsCredential = $SqlAdministratorCredential

            DependsOn            = '[SqlServerEndpoint]HADREndpoint', '[SqlServerLogin]AddComputerAccountLoginPrimaryReplica'
        }

        SqlServerEndpointPermission SQLConfigureEndpointPermissionSecondary
        {
            Ensure               = 'Present'
            ServerName           = $Node.NodeName
            InstanceName         = $Node.InstanceName
            Name                 = 'HADR'
            Principal            = ( $AllNodes | Where-Object { $_.Role -eq 'SecondaryReplica' } ).ComputerAccountName
            Permission           = 'CONNECT'
            PsDscRunAsCredential = $SqlAdministratorCredential

            DependsOn            = '[SqlServerEndpoint]HADREndpoint', '[SqlServerLogin]AddComputerAccountLoginSecondaryReplica'
        }

        # Enable AlwaysOn functionality after cluster creation
        SqlAlwaysOnService EnableHADR
        {
            Ensure               = 'Present'
            InstanceName         = $Node.InstanceName
            ServerName           = $Node.NodeName
            PsDscRunAsCredential = $SqlAdministratorCredential

            DependsOn            = '[SqlSetup]InstallDefaultInstance', $(if($Node.Role -eq "PrimaryReplica") { '[xCluster]CreateCluster' } else { '[xCluster]JoinSecondNodeToCluster'})
        }
        #endregion

        #endregion

        #region First node activities
        if($Node.Role -eq "PrimaryReplica") {

            # On first server, create cluster
            xCluster CreateCluster
            {
                Name                          = $Node.ClusterName
                StaticIPAddress               = $Node.ClusterIPAddress
                # This user must have the permission to create the CNO (Cluster Name Object) in Active Directory, unless it is prestaged.
                DomainAdministratorCredential = $ActiveDirectoryAdministratorCredential
                
                DependsOn                     = '[WindowsFeature]AddRsatCluster'
            }

            # Create dummy database
            SqlDatabase DummyDB {
                Ensure              = 'Present'
                ServerName          = $Node.NodeName
                InstanceName        = $Node.InstanceName
                Name                = 'DummyDB'

                DependsOn           = '[SqlSetup]InstallDefaultInstance'
            }

            # Create the availability group on the instance tagged as the primary replica
            SqlAG AddAlwaysOnAG
            {
                Ensure                        = 'Present'
                Name                          = $Node.AGName
                InstanceName                  = $Node.InstanceName
                ServerName                    = $Node.NodeName
                ProcessOnlyOnActiveNode       = $Node.ProcessOnlyOnActiveNode

                AvailabilityMode              = $Node.AvailabilityMode
                BackupPriority                = $Node.BackupPriority
                ConnectionModeInPrimaryRole   = $Node.ConnectionModeInPrimaryRole
                ConnectionModeInSecondaryRole = $Node.ConnectionModeInSecondaryRole
                FailoverMode                  = $Node.FailoverMode

                PsDscRunAsCredential = $SqlAdministratorCredential

                DependsOn            = '[SqlAlwaysOnService]EnableHADR', '[SqlServerEndpoint]HADREndpoint', '[SqlServerPermission]AddSystemAccountPermissions', '[SqlServerPermission]AddClusSvcPermissions', '[SqlServerEndpointPermission]SQLConfigureEndpointPermissionPrimary', '[SqlServerEndpointPermission]SQLConfigureEndpointPermissionSecondary', '[SqlDatabase]DummyDB'
            }

            # Share SQL Backup folder to seed availability group database - low security for demo purposes
            xSmbShare SqlBackupShare {

                Ensure              = "Present"
                Name                = "SQLBackup"
                Path                = $Node.SqlBackupPath
                FullAccess          = "Everyone"
                
                DependsOn           = '[SqlSetup]InstallDefaultInstance'
            }

            cNtfsPermissionEntry PermissionSet1
            {
                Ensure              = 'Present'
                Path                = $Node.SqlBackupPath
                Principal           = ( $AllNodes | Where-Object { $_.Role -eq 'SecondaryReplica' } ).ComputerAccountName
                AccessControlInformation = @(
                    cNtfsAccessControlInformation
                    {
                        AccessControlType   = 'Allow'
                        FileSystemRights    = 'Modify'
                        Inheritance         = 'ThisFolderSubfoldersAndFiles'
                        NoPropagateInherit  = $false
                    }
                )
                DependsOn           = '[SqlSetup]InstallDefaultInstance'
            }
            
            # Add AG Listener
            SqlAGListener AGListener
            {
                Ensure                  = 'Present'
                ServerName              = $Node.NodeName
                InstanceName            = $Node.InstanceName
                AvailabilityGroup       = $Node.AGName
                Name                    = 'DemoAGvip'
                IpAddress               = '192.168.100.150/255.255.255.0'
                Port                    = 1433
                PsDscRunAsCredential    = $SqlAdministratorCredential

                DependsOn               = '[SqlAg]AddAlwaysOnAG'
            }
        }
        #endregion

        #region Second node activities
        if($Node.Role -eq "SecondaryReplica") {

            # On second server, wait for cluster creation and join it
            xWaitForCluster WaitForCluster
            {
                Name                 = $Node.ClusterName
                RetryIntervalSec     = 10
                RetryCount           = 60
                PsDscRunAsCredential = $ActiveDirectoryAdministratorCredential
                
                DependsOn        = '[WindowsFeature]AddRsatCluster'
            }

            xCluster JoinSecondNodeToCluster
            {
                Name                          = $Node.ClusterName
                StaticIPAddress               = $Node.ClusterIPAddress
                DomainAdministratorCredential = $ActiveDirectoryAdministratorCredential
                PsDscRunAsCredential          = $ActiveDirectoryAdministratorCredential
                
                DependsOn                     = '[xWaitForCluster]WaitForCluster'
            }

            # Add the availability group replica to the availability group
            SqlWaitForAG WaitForDemoAG
            {
                Name                 = $Node.AGName
                RetryIntervalSec     = 20
                RetryCount           = 30
                PsDscRunAsCredential = $SqlAdministratorCredential

                DependsOn            = '[xCluster]JoinSecondNodeToCluster'
            }

            SqlAGReplica AddReplica
            {
                Ensure                        = 'Present'
                Name                          = $Node.NodeName
                AvailabilityGroupName         = $Node.AGName
                ServerName                    = $Node.NodeName
                InstanceName                  = $Node.InstanceName
                PrimaryReplicaServerName      = ( $AllNodes | Where-Object { $_.Role -eq 'PrimaryReplica' } ).NodeName
                PrimaryReplicaInstanceName    = ( $AllNodes | Where-Object { $_.Role -eq 'PrimaryReplica' } ).InstanceName
                AvailabilityMode              = $Node.AvailabilityMode
                BackupPriority                = $Node.BackupPriority
                ConnectionModeInPrimaryRole   = $Node.ConnectionModeInPrimaryRole
                ConnectionModeInSecondaryRole = $Node.ConnectionModeInSecondaryRole
                FailoverMode                  = $Node.FailoverMode
                ProcessOnlyOnActiveNode       = $Node.ProcessOnlyOnActiveNode
                PsDscRunAsCredential          = $SqlAdministratorCredential

                DependsOn                     = '[SqlWaitForAG]WaitForDemoAG'
            }

            # Add DummyDB to DemoAG
            SqlAGDatabase 'AddDummyDBtoAG'
            {
                Ensure                  = 'Present'
                AvailabilityGroupName   = $Node.AGName
                BackupPath              = "\\$(($AllNodes | Where-Object { $_.Role -eq 'PrimaryReplica' }).NodeName)\SQLBackup"
                DatabaseName            = 'DummyDB'
                InstanceName            = ( $AllNodes | Where-Object { $_.Role -eq 'PrimaryReplica' } ).InstanceName
                ServerName              = ( $AllNodes | Where-Object { $_.Role -eq 'PrimaryReplica' } ).NodeName
                PsDscRunAsCredential    = $SqlAdministratorCredential

                DependsOn               = '[SqlAgReplica]AddReplica'
            }

        }
        #endregion
        
    }
#endregion
}
