-- Sanitized sample from an internal infrastructure monitoring project.
-- Secrets, internal identifiers, and localized text have been removed or generalized.

IF OBJECT_ID(N'fact.ServerReboot', N'U') IS NULL
BEGIN
    CREATE TABLE [fact].[ServerReboot] (
        [ServerRebootId]     BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [ServerId]           INT                  NOT NULL,
        [BootTime]           DATETIME2(0)         NOT NULL,
        [ShutdownTime]       DATETIME2(0)          NULL,
        [PreviousUptimeHours] DECIMAL(18,2)       NULL,
        [Reason]             NVARCHAR(255)        NULL,   -- Planned / Crash / Update / ...
        [InitiatedByUserId]  INT                  NULL,
        [InitiatedByRaw]     NVARCHAR(255)        NULL,
        [Source]             NVARCHAR(50)         NULL    -- script / eventlog
    );

    ALTER TABLE [fact].[ServerReboot]  WITH CHECK ADD
        CONSTRAINT FK_ServerReboot_Server
            FOREIGN KEY ([ServerId]) REFERENCES [dim].[Server]([ServerId]);

    ALTER TABLE [fact].[ServerReboot]  WITH CHECK ADD
        CONSTRAINT FK_ServerReboot_User
            FOREIGN KEY ([InitiatedByUserId]) REFERENCES [dim].[User]([UserId]);

    CREATE INDEX IX_ServerReboot_Server_Boot
        ON [fact].[ServerReboot]([ServerId], [BootTime]);
    
    PRINT 'Sanitized label';
END
ELSE
BEGIN
    PRINT 'Sanitized label';
    
    IF NOT EXISTS (
        SELECT * FROM INFORMATION_SCHEMA.COLUMNS 
        WHERE TABLE_SCHEMA = 'fact' 
        AND TABLE_NAME = 'ServerReboot' 
        AND COLUMN_NAME = 'ShutdownTime'
    )
    BEGIN
        ALTER TABLE [fact].[ServerReboot]
        ADD [ShutdownTime] DATETIME2(0) NULL;
        
        PRINT 'Sanitized label';
    END
    ELSE
    BEGIN
        PRINT 'Sanitized label';
    END
END
GO

