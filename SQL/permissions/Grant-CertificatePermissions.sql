-- Sanitized sample from an internal infrastructure monitoring project.
-- Secrets, internal identifiers, and localized text have been removed or generalized.

-- Grant permissions for AD Certificate Status
GRANT INSERT ON fact.AdCertificateStatus TO <SQL_SERVICE_ACCOUNT>;
GRANT SELECT ON fact.AdCertificateStatus TO <SQL_SERVICE_ACCOUNT>;
GO

