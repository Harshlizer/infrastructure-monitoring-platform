-- Sanitized sample from an internal infrastructure monitoring project.
-- Secrets, internal identifiers, and localized text have been removed or generalized.

SELECT TOP 20
    r.ServerRebootId,
    s.ServerName,
    r.BootTime,
    r.ShutdownTime,
    r.Reason,
    r.InitiatedByRaw,
    u.DisplayName,
    u.UPN,
    r.Source,
    r.BootTime AS BootTimeUTC
FROM fact.ServerReboot AS r
JOIN dim.Server AS s ON s.ServerId = r.ServerId
LEFT JOIN dim.[User] AS u ON u.UserId = r.InitiatedByUserId
ORDER BY r.BootTime DESC;

SELECT 
    r.ServerRebootId,
    s.ServerName,
    r.BootTime,
    r.ShutdownTime,
    r.Reason,
    r.InitiatedByRaw
FROM fact.ServerReboot AS r
JOIN dim.Server AS s ON s.ServerId = r.ServerId
WHERE s.ServerName LIKE '%<DOMAIN_CONTROLLER>%' OR s.ServerName LIKE '%<DOMAIN_CONTROLLER>%'
ORDER BY r.BootTime DESC;

SELECT ServerId, ServerName, IsActive, CreatedAt
FROM dim.Server
WHERE ServerName LIKE '%DC07%' OR ServerName LIKE '%dc07%'
ORDER BY ServerName;

SELECT 
    COUNT(*) AS TotalReboots,
    MIN(BootTime) AS FirstBoot,
    MAX(BootTime) AS LastBoot
FROM fact.ServerReboot;

