-- Sanitized sample from an internal infrastructure monitoring project.
-- Secrets, internal identifiers, and localized text have been removed or generalized.

-- ============================================
-- ============================================
-- ============================================

USE [Monitoring];
GO

SELECT 
    COUNT(*) AS [TotalRecords],
    COUNT(DISTINCT ServerId) AS [UniqueServers],
    MIN(CaptureTime) AS [OldestRecord],
    MAX(CaptureTime) AS [NewestRecord]
FROM [fact].[AdCertificateStatus];
GO

DELETE FROM [fact].[AdCertificateStatus];
GO

SELECT COUNT(*) AS [RemainingRecords] FROM [fact].[AdCertificateStatus];
GO

PRINT 'Sanitized label';
PRINT 'Sanitized label';
GO

