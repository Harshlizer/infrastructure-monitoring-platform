-- Sanitized sample from an internal infrastructure monitoring project.
-- Secrets, internal identifiers, and localized text have been removed or generalized.

-- Script to check how data is stored in fact.AdGroupEvent table
-- Run this to see what fields contain information about who performed the action

-- Check table structure
SELECT 
    COLUMN_NAME,
    DATA_TYPE,
    IS_NULLABLE,
    CHARACTER_MAXIMUM_LENGTH
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'fact' 
  AND TABLE_NAME = 'AdGroupEvent'
ORDER BY ORDINAL_POSITION;
GO

-- Check sample data with all relevant fields
SELECT TOP 20
    EventTime,
    TargetGroup,
    MemberName,
    MemberType,
    Action,
    PerformedByUserId,
    PerformedByRaw,
    Source,
    DomainControllerId
FROM fact.AdGroupEvent
ORDER BY EventTime DESC;
GO

-- Check if PerformedByUserId has values and join with dim.User
SELECT TOP 20
    g.EventTime,
    g.TargetGroup,
    g.MemberName,
    g.Action,
    g.PerformedByUserId,
    g.PerformedByRaw,
    u.UPN,
    u.DisplayName
FROM fact.AdGroupEvent AS g
LEFT JOIN [dim].[User] AS u ON u.UserId = g.PerformedByUserId
ORDER BY g.EventTime DESC;
GO

-- Check distinct values in PerformedByRaw
SELECT DISTINCT 
    PerformedByRaw,
    COUNT(*) AS Count
FROM fact.AdGroupEvent
WHERE PerformedByRaw IS NOT NULL
GROUP BY PerformedByRaw
ORDER BY Count DESC;
GO

