-- Sanitized sample from an internal infrastructure monitoring project.
-- Secrets, internal identifiers, and localized text have been removed or generalized.

IF OBJECT_ID(N'fact.M365InactiveUser', N'U') IS NULL
BEGIN
    CREATE TABLE [fact].[M365InactiveUser] (
        [M365InactiveUserId] BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [SnapshotDate]       DATE                 NOT NULL,
        [DisplayName]        NVARCHAR(255)        NOT NULL,
        [UserPrincipalName] NVARCHAR(255)        NOT NULL,
        [Email]             NVARCHAR(255)        NULL,
        [LastActivity]      DATETIME2(0)         NULL,
        [DaysSinceLastActivity] INT              NULL,
        [Licenses]          NVARCHAR(MAX)         NULL,  --    
        [MonthlyCost]       DECIMAL(18,2)         NOT NULL,
        [Source]            NVARCHAR(50)          NULL
    );

    CREATE INDEX IX_M365InactiveUser_SnapshotDate
        ON [fact].[M365InactiveUser]([SnapshotDate] DESC);
    
    CREATE INDEX IX_M365InactiveUser_DaysInactive
        ON [fact].[M365InactiveUser]([DaysSinceLastActivity] DESC);
    
    PRINT 'Sanitized label';
END
ELSE
BEGIN
    PRINT 'Sanitized label';
END
GO

