-- Sanitized sample from an internal infrastructure monitoring project.
-- Secrets, internal identifiers, and localized text have been removed or generalized.

IF OBJECT_ID(N'fact.BackupGcpBucket', N'U') IS NULL
BEGIN
    CREATE TABLE [fact].[BackupGcpBucket] (
        [BackupGcpBucketId]   BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [ServerId]             INT                  NULL,           -- FK  dim.Server
        [ServerName]            NVARCHAR(255)        NOT NULL,       --  
        [DatabaseName]          NVARCHAR(255)         NOT NULL,       --   
        [BackupDate]            DATETIME2(0)          NOT NULL,       --   
        [BucketName]            NVARCHAR(255)         NOT NULL,       --  GCP bucket
        [FileName]              NVARCHAR(500)         NOT NULL,       --    bucket
        [FileSize]              BIGINT                NULL,           --    
        [UploadedDate]          DATETIME2(0)          NULL,           --    bucket
        [IsUploaded]            BIT                   NOT NULL DEFAULT 0,  --   
        [GcpProjectId]          NVARCHAR(255)         NULL,           -- GCP Project ID
        [CheckTime]             DATETIME2(0)          NOT NULL DEFAULT SYSDATETIME(),  --  
        [Source]                NVARCHAR(100)         NOT NULL DEFAULT 'Check-BackupGcpBuckets'  --  
    );
    
    CREATE NONCLUSTERED INDEX IX_BackupGcpBucket_Server_Database_BackupDate 
        ON [fact].[BackupGcpBucket] ([ServerName], [DatabaseName], [BackupDate] DESC);
    
    CREATE NONCLUSTERED INDEX IX_BackupGcpBucket_BucketName 
        ON [fact].[BackupGcpBucket] ([BucketName]);
    
    PRINT 'Sanitized label';
END
ELSE
BEGIN
    PRINT 'Sanitized label';
END
GO

