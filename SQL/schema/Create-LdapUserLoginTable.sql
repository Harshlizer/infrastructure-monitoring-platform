-- Sanitized sample from an internal infrastructure monitoring project.
-- Secrets, internal identifiers, and localized text have been removed or generalized.

-- Create table for LDAP user logins (non-LDAPS)
IF OBJECT_ID(N'fact.LdapUserLogin', N'U') IS NULL
BEGIN
    CREATE TABLE [fact].[LdapUserLogin] (
        [LdapUserLoginId] BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [LoginDate]        DATETIME2(0)         NOT NULL,
        [ServerId]          INT                  NOT NULL,   -- DC
        [UserName]          NVARCHAR(255)        NOT NULL,
        [ClientIpAddress]  NVARCHAR(50)         NULL,
        [EventId]           INT                  NULL,
        [Message]           NVARCHAR(MAX)        NULL
    );

    ALTER TABLE [fact].[LdapUserLogin]  WITH CHECK ADD
        CONSTRAINT FK_LdapUserLogin_Server
            FOREIGN KEY ([ServerId]) REFERENCES [dim].[Server]([ServerId]);

    CREATE INDEX IX_LdapUserLogin_Date
        ON [fact].[LdapUserLogin]([LoginDate]);

    CREATE INDEX IX_LdapUserLogin_ServerDate
        ON [fact].[LdapUserLogin]([ServerId], [LoginDate]);

    CREATE INDEX IX_LdapUserLogin_User
        ON [fact].[LdapUserLogin]([UserName]);
END;
GO

-- Grant permissions
GRANT INSERT ON fact.LdapUserLogin TO <SQL_SERVICE_ACCOUNT>;
GRANT SELECT ON fact.LdapUserLogin TO <SQL_SERVICE_ACCOUNT>;
GO

