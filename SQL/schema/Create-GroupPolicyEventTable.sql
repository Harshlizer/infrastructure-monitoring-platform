-- Sanitized sample from an internal infrastructure monitoring project.
-- Secrets, internal identifiers, and localized text have been removed or generalized.

IF OBJECT_ID(N'fact.GroupPolicyEvent', N'U') IS NULL
BEGIN
    CREATE TABLE [fact].[GroupPolicyEvent] (
        [GroupPolicyEventId]   BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [EventTime]            DATETIME2(0)         NOT NULL,       --  
        [DomainControllerId]   INT                  NULL,           -- FK  dim.Server (DC)
        [GpoName]              NVARCHAR(500)        NOT NULL,       --  GPO
        [GpoGuid]              NVARCHAR(100)        NULL,           -- GUID GPO
        [Action]                NVARCHAR(50)        NOT NULL,       -- Created / Modified / Deleted / Moved
        [EventId]               INT                  NOT NULL,       -- Event ID (5136, 5137, 5139, 5141)
        [PerformedByUserId]     INT                  NULL,           -- FK  dim.User
        [PerformedByRaw]        NVARCHAR(255)        NULL,           --     
        [Source]                NVARCHAR(50)         NULL            --  / 
    );
    
    CREATE NONCLUSTERED INDEX IX_GroupPolicyEvent_EventTime_DC 
        ON [fact].[GroupPolicyEvent] ([EventTime] DESC, [DomainControllerId]);
    
    CREATE NONCLUSTERED INDEX IX_GroupPolicyEvent_GpoGuid 
        ON [fact].[GroupPolicyEvent] ([GpoGuid]);
    
    PRINT 'Sanitized label';
END
ELSE
BEGIN
    PRINT 'Sanitized label';
END
GO

