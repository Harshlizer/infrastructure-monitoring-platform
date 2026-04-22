-- Sanitized sample from an internal infrastructure monitoring project.
-- Secrets, internal identifiers, and localized text have been removed or generalized.

USE [Monitoring];
GO

GRANT INSERT ON [fact].[AdGroupEvent] TO [<SQL_SERVICE_ACCOUNT>];
GO

GRANT SELECT ON [dim].[Server] TO [<SQL_SERVICE_ACCOUNT>];
GO

GRANT INSERT ON [dim].[Server] TO [<SQL_SERVICE_ACCOUNT>];
GO

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
  AND o.name IN ('AdGroupEvent', 'Server', 'User')
  AND s.name IN ('fact', 'dim')
ORDER BY s.name, o.name, p.permission_name;
GO

PRINT 'Sanitized label';
GO

