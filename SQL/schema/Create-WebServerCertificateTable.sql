-- Sanitized sample from an internal infrastructure monitoring project.
-- Secrets, internal identifiers, and localized text have been removed or generalized.

IF OBJECT_ID(N'fact.WebServerCertificate', N'U') IS NULL
BEGIN
    CREATE TABLE [fact].[WebServerCertificate] (
        [WebServerCertificateId] BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [SiteName]               NVARCHAR(255)        NOT NULL,  --   (, ,  ..)
        [Url]                    NVARCHAR(500)         NOT NULL,  -- URL 
        [CertificateSubject]      NVARCHAR(500)         NULL,      -- Subject 
        [CertificateIssuer]      NVARCHAR(500)         NULL,      -- Issuer 
        [ExpirationDate]         DATETIME2(0)          NOT NULL,  --   
        [DaysRemaining]          INT                   NOT NULL,  --    
        [Severity]               NVARCHAR(20)          NOT NULL,  -- green, yellow, red
        [Thumbprint]             NVARCHAR(100)          NULL,      -- Thumbprint 
        [CaptureTime]            DATETIME2(0)          NOT NULL DEFAULT SYSDATETIME(),  --  
        [Source]                 NVARCHAR(100)         NOT NULL DEFAULT 'Check-WebServerCertificates',  --  
        CONSTRAINT CHK_WebServerCertificate_Severity CHECK ([Severity] IN ('green', 'yellow', 'red'))
    );
    
    CREATE NONCLUSTERED INDEX IX_WebServerCertificate_Url_CaptureTime 
        ON [fact].[WebServerCertificate] ([Url], [CaptureTime] DESC);
    
    PRINT 'Sanitized label';
END
ELSE
BEGIN
    PRINT 'Sanitized label';
END
GO

