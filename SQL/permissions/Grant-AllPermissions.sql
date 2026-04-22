-- Sanitized sample from an internal infrastructure monitoring project.
-- Secrets, internal identifiers, and localized text have been removed or generalized.

USE [Monitoring];
GO

PRINT 'Sanitized label';
GO

-- ===== Firewall Status =====
GRANT INSERT ON [fact].[FirewallStatus] TO [<SQL_SERVICE_ACCOUNT>];
GO

-- ===== DNS Events =====
GRANT INSERT ON [fact].[DnsZoneEvent] TO [<SQL_SERVICE_ACCOUNT>];
GRANT INSERT ON [fact].[DnsRecordEvent] TO [<SQL_SERVICE_ACCOUNT>];
GO

-- ===== AD Events =====
GRANT INSERT ON [fact].[AdGroupEvent] TO [<SQL_SERVICE_ACCOUNT>];
GO

-- ===== Group Policy Events =====
GRANT INSERT ON [fact].[GroupPolicyEvent] TO [<SQL_SERVICE_ACCOUNT>];
GO

-- ===== Backup GCP Bucket =====
GRANT INSERT ON [fact].[BackupGcpBucket] TO [<SQL_SERVICE_ACCOUNT>];
GRANT DELETE ON [fact].[BackupGcpBucket] TO [<SQL_SERVICE_ACCOUNT>];
GO

-- ===== Software Audit =====
GRANT INSERT ON [fact].[SoftwareAudit] TO [<SQL_SERVICE_ACCOUNT>];
GO

-- ===== AD Certificate Status =====
GRANT INSERT ON [fact].[AdCertificateStatus] TO [<SQL_SERVICE_ACCOUNT>];
GO

-- ===== LDAP User Login =====
GRANT INSERT ON [fact].[LdapUserLogin] TO [<SQL_SERVICE_ACCOUNT>];
GO

-- ===== Server Reboot =====
GRANT INSERT ON [fact].[ServerReboot] TO [<SQL_SERVICE_ACCOUNT>];
GO

-- ===== M365 Inactive User =====
GRANT INSERT ON [fact].[M365InactiveUser] TO [<SQL_SERVICE_ACCOUNT>];
GRANT DELETE ON [fact].[M365InactiveUser] TO [<SQL_SERVICE_ACCOUNT>];
GO

-- ===== M365 License Cost by Department =====
GRANT INSERT ON [fact].[M365LicenseCostByDepartment] TO [<SQL_SERVICE_ACCOUNT>];
GRANT DELETE ON [fact].[M365LicenseCostByDepartment] TO [<SQL_SERVICE_ACCOUNT>];
GO

-- ===== Web Server Certificate =====
GRANT INSERT ON [fact].[WebServerCertificate] TO [<SQL_SERVICE_ACCOUNT>];
GRANT DELETE ON [fact].[WebServerCertificate] TO [<SQL_SERVICE_ACCOUNT>];
GO

-- ===== SQL Job Run =====
GRANT INSERT ON [fact].[SqlJobRun] TO [<SQL_SERVICE_ACCOUNT>];
GO

-- ===== Dim Tables =====
GRANT SELECT ON [dim].[Server] TO [<SQL_SERVICE_ACCOUNT>];
GRANT INSERT ON [dim].[Server] TO [<SQL_SERVICE_ACCOUNT>];
GRANT SELECT ON [dim].[User] TO [<SQL_SERVICE_ACCOUNT>];
GRANT INSERT ON [dim].[User] TO [<SQL_SERVICE_ACCOUNT>];
GO

SELECT 
    p.permission_name,
    p.state_desc,
    pr.name AS principal_name,
    o.name AS object_name,
    s.name AS schema_name
FROM sys.database_permissions p
INNER JOIN sys.database_principals pr ON p.grantee_principal_id = pr.principal_id
INNER JOIN sys.objects o ON p.major_id = o.object_id
INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE pr.name = '<SQL_SERVICE_ACCOUNT>'
  AND o.name IN ('FirewallStatus', 'DnsZoneEvent', 'DnsRecordEvent', 'AdGroupEvent', 'SoftwareAudit', 'AdCertificateStatus', 'LdapUserLogin', 'ServerReboot', 'SqlJobRun', 'Server', 'User')
  AND s.name IN ('fact', 'dim')
ORDER BY s.name, o.name, p.permission_name;
GO

PRINT 'Sanitized label';
GO

