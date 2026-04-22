-- Sanitized sample from an internal infrastructure monitoring project.
-- Secrets, internal identifiers, and localized text have been removed or generalized.

IF OBJECT_ID(N'fact.M365LicenseCostByDepartment', N'U') IS NULL
BEGIN
    CREATE TABLE [fact].[M365LicenseCostByDepartment] (
        [M365LicenseCostId] BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [SnapshotDate]      DATE                 NOT NULL,
        [Department]        NVARCHAR(255)        NOT NULL,
        [TotalCost]         DECIMAL(18,2)        NOT NULL,
        [ENTERPRISEPACK]    INT                  NOT NULL DEFAULT 0,
        [F1]                INT                  NOT NULL DEFAULT 0,
        [F1_FIRSTLINE]      INT                  NOT NULL DEFAULT 0,
        [M365_F1]           INT                  NOT NULL DEFAULT 0,
        [M365_F1_COMM]      INT                  NOT NULL DEFAULT 0,
        [MICROSOFT_365_F1]  INT                  NOT NULL DEFAULT 0,
        [O365_BUSINESS]     INT                  NOT NULL DEFAULT 0,
        [O365_BUSINESS_ESSENTIALS] INT           NOT NULL DEFAULT 0,
        [O365_BUSINESS_PREMIUM] INT             NOT NULL DEFAULT 0,
        [O365_F1]           INT                  NOT NULL DEFAULT 0,
        [O365_STANDARD]     INT                  NOT NULL DEFAULT 0,
        [OFFICE_365_F1]     INT                  NOT NULL DEFAULT 0,
        [OFFICESUBSCRIPTION] INT                 NOT NULL DEFAULT 0,
        [POWER_BI_PREMIUM_PER_USER] INT          NOT NULL DEFAULT 0,
        [POWER_BI_PRO]      INT                  NOT NULL DEFAULT 0,
        [SPB]               INT                  NOT NULL DEFAULT 0,
        [SPE_F1]            INT                  NOT NULL DEFAULT 0,
        [STANDARDPACK]      INT                  NOT NULL DEFAULT 0,
        [TEAMS_ESSENTIALS]  INT                  NOT NULL DEFAULT 0,
        [TEAMS_PREMIUM]     INT                  NOT NULL DEFAULT 0,
        [Source]            NVARCHAR(100)        NULL
    );

    CREATE INDEX IX_M365LicenseCost_SnapshotDate
        ON [fact].[M365LicenseCostByDepartment]([SnapshotDate] DESC);
    
    CREATE INDEX IX_M365LicenseCost_Department
        ON [fact].[M365LicenseCostByDepartment]([Department]);
    
    PRINT 'Sanitized label';
END
ELSE
BEGIN
    PRINT 'Sanitized label';
END
GO

