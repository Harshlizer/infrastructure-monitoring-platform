-- Sanitized sample from an internal infrastructure monitoring project.
-- Secrets, internal identifiers, and localized text have been removed or generalized.

-- ============================================
-- ============================================
-- ============================================

USE [Monitoring];
GO

SELECT 
    ServerId,
    ServerName,
    IpAddress,
    IsActive,
    CreatedAt
FROM [dim].[Server]
WHERE IpAddress = '<INTERNAL_IP>' OR ServerName LIKE '%<INTERNAL_IP>%';
GO

UPDATE [dim].[Server]
SET IsActive = 0
WHERE IpAddress = '<INTERNAL_IP>' OR ServerName LIKE '%<INTERNAL_IP>%';
GO

SELECT 
    ServerId,
    ServerName,
    IpAddress,
    IsActive,
    CreatedAt
FROM [dim].[Server]
WHERE IpAddress = '<INTERNAL_IP>' OR ServerName LIKE '%<INTERNAL_IP>%';
GO

-- ============================================
-- ============================================

/*
DELETE FROM [fact].[SqlJobRun]
WHERE ServerId IN (
    SELECT ServerId FROM [dim].[Server]
    WHERE IpAddress = '<INTERNAL_IP>' OR ServerName LIKE '%<INTERNAL_IP>%'
);

DELETE FROM [dim].[Server]
WHERE IpAddress = '<INTERNAL_IP>' OR ServerName LIKE '%<INTERNAL_IP>%';
*/
GO

PRINT 'Sanitized label';
PRINT 'Sanitized label';
GO

