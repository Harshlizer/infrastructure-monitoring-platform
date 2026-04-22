-- Sanitized sample from an internal infrastructure monitoring project.
-- Secrets, internal identifiers, and localized text have been removed or generalized.

IF EXISTS (
    SELECT * FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_SCHEMA = 'fact' 
    AND TABLE_NAME = 'M365LicenseCostByDepartment' 
    AND COLUMN_NAME = 'Source'
    AND CHARACTER_MAXIMUM_LENGTH = 50
)
BEGIN
    ALTER TABLE [fact].[M365LicenseCostByDepartment]
    ALTER COLUMN [Source] NVARCHAR(100) NULL;
    
    PRINT 'Sanitized label';
END
ELSE IF EXISTS (
    SELECT * FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_SCHEMA = 'fact' 
    AND TABLE_NAME = 'M365LicenseCostByDepartment' 
    AND COLUMN_NAME = 'Source'
)
BEGIN
    PRINT 'Sanitized label';
END
ELSE
BEGIN
    PRINT 'Sanitized label';
END
GO

