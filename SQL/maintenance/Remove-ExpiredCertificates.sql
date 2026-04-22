-- Sanitized sample from an internal infrastructure monitoring project.
-- Secrets, internal identifiers, and localized text have been removed or generalized.

-- ============================================
-- ============================================
-- ============================================

USE [Monitoring];
GO

SELECT 
    COUNT(*) AS [TotalExpired],
    COUNT(DISTINCT ServerId) AS [AffectedServers]
FROM [fact].[AdCertificateStatus]
WHERE DaysRemaining < 0
   OR (CertificateName LIKE '%Microsoft Time Stamping Service Root%' 
       AND ExpirationDate < DATEADD(YEAR, -10, GETDATE()));
GO

DELETE FROM [fact].[AdCertificateStatus]
WHERE DaysRemaining < 0
   OR (CertificateName LIKE '%Microsoft Time Stamping Service Root%' 
       AND ExpirationDate < DATEADD(YEAR, -10, GETDATE()));
GO

SELECT 
    COUNT(*) AS [RemainingCertificates],
    COUNT(DISTINCT ServerId) AS [ServersWithCertificates]
FROM [fact].[AdCertificateStatus];
GO

PRINT 'Sanitized label';
PRINT 'Sanitized label';
GO

