-- Sanitized sample from an internal infrastructure monitoring project.
-- Secrets, internal identifiers, and localized text have been removed or generalized.

-- Add Message column to DNS event tables if it doesn't exist

-- For DnsZoneEvent
IF NOT EXISTS (
    SELECT * FROM sys.columns 
    WHERE object_id = OBJECT_ID(N'fact.DnsZoneEvent') 
    AND name = 'Message'
)
BEGIN
    ALTER TABLE fact.DnsZoneEvent
    ADD Message NVARCHAR(MAX) NULL;
END
GO

-- For DnsRecordEvent
IF NOT EXISTS (
    SELECT * FROM sys.columns 
    WHERE object_id = OBJECT_ID(N'fact.DnsRecordEvent') 
    AND name = 'Message'
)
BEGIN
    ALTER TABLE fact.DnsRecordEvent
    ADD Message NVARCHAR(MAX) NULL;
END
GO

