-- Sanitized sample from an internal infrastructure monitoring project.
-- Secrets, internal identifiers, and localized text have been removed or generalized.

IF OBJECT_ID(N'fact.ServerReboot', N'U') IS NULL
BEGIN
    PRINT 'Sanitized label';
    PRINT 'Sanitized label';
    RETURN;
END

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
GO

