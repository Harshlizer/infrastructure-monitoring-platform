using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.AspNetCore.Authentication.Negotiate;

var builder = WebApplication.CreateBuilder(args);

// ----- Connection string -----
var connString = builder.Configuration.GetConnectionString("MonitoringDb");

// ----- Windows Authentication -----
builder.Services.AddAuthentication(NegotiateDefaults.AuthenticationScheme)
    .AddNegotiate();

builder.Services.AddAuthorization();

var app = builder.Build();

app.UseAuthentication();
app.UseAuthorization();

// Serve static assets and the dashboard shell
app.UseDefaultFiles();
app.UseStaticFiles();

// ===== Diagnostic identity endpoint =====
app.MapGet("/api/whoami", (HttpContext ctx) =>
{
    var user = ctx.User?.Identity?.Name ?? "anonymous";
    return Results.Ok(new { user });
});

// ===== Helper to parse date filters =====
DateTime? ParseDate(string? dateStr)
{
    if (string.IsNullOrWhiteSpace(dateStr))
        return null;
    if (DateTime.TryParse(dateStr, out var date))
        return date.Date;
    return null;
}

// ===== /api/sql-jobs (job runs for a selected period) =====
app.MapGet("/api/sql-jobs", async (HttpContext ctx) =>
{
    var dateFromStr = ctx.Request.Query["dateFrom"].ToString();
    var dateToStr = ctx.Request.Query["dateTo"].ToString();
    var dateStr = ctx.Request.Query["date"].ToString();
    
    DateTime dateFrom, dateTo;
    
    // If a single date is provided, use that day range
    if (!string.IsNullOrWhiteSpace(dateStr) && DateTime.TryParse(dateStr, out var singleDate))
    {
        dateFrom = singleDate.Date;
        dateTo = singleDate.Date.AddDays(1).AddSeconds(-1);
    }
    // If a date range is provided
    else if (!string.IsNullOrWhiteSpace(dateFromStr) && !string.IsNullOrWhiteSpace(dateToStr))
    {
        if (!DateTime.TryParse(dateFromStr, out dateFrom))
            dateFrom = DateTime.UtcNow.Date;
        if (!DateTime.TryParse(dateToStr, out dateTo))
            dateTo = DateTime.UtcNow.Date.AddDays(1).AddSeconds(-1);
        else
            dateTo = dateTo.Date.AddDays(1).AddSeconds(-1);
    }
    // Default to the last 24 hours
    else
    {
        dateTo = DateTime.UtcNow;
        dateFrom = dateTo.AddDays(-1);
    }

    string? server = ctx.Request.Query["server"].ToString();
    if (string.IsNullOrWhiteSpace(server))
        server = null;

    using var conn = new SqlConnection(connString);
    await conn.OpenAsync();

    var cmd = conn.CreateCommand();
    cmd.CommandText = @"
SELECT TOP (500)
    j.CaptureTime,
    s.ServerName,
    j.JobName,
    j.LastStatus,
    j.LastRunTime,
    j.Message
FROM fact.SqlJobRun AS j
JOIN dim.Server AS s ON s.ServerId = j.ServerId
WHERE j.CaptureTime >= @DateFrom AND j.CaptureTime <= @DateTo
  AND (@Server IS NULL OR s.ServerName = @Server)
ORDER BY j.CaptureTime DESC;
";
    cmd.Parameters.Add(new SqlParameter("@DateFrom", SqlDbType.DateTime2) { Value = dateFrom });
    cmd.Parameters.Add(new SqlParameter("@DateTo", SqlDbType.DateTime2) { Value = dateTo });
    cmd.Parameters.Add(new SqlParameter("@Server", SqlDbType.NVarChar, 255)
    {
        Value = (object?)server ?? DBNull.Value
    });

    var reader = await cmd.ExecuteReaderAsync();
    var list = new List<object>();
    while (await reader.ReadAsync())
    {
        list.Add(new
        {
            captureTime = reader.GetDateTime(0),
            serverName  = reader.GetString(1),
            jobName     = reader.GetString(2),
            lastStatus  = reader.GetString(3),
            lastRunTime = reader.IsDBNull(4) ? (DateTime?)null : reader.GetDateTime(4),
            message     = reader.IsDBNull(5) ? null : reader.GetString(5)
        });
    }

    return Results.Json(list);
});

// ===== /api/sql-agent-status (agent health snapshot) =====
app.MapGet("/api/sql-agent-status", async (HttpContext ctx) =>
{
    try
    {
        string? server = ctx.Request.Query["server"].ToString();
        if (string.IsNullOrWhiteSpace(server))
            server = null;

        using var conn = new SqlConnection(connString);
        await conn.OpenAsync();

        var cmd = conn.CreateCommand();
        cmd.CommandText = @"
WITH LatestAgent AS (
    SELECT 
        j.ServerId,
        j.AgentStatus,
        j.CaptureTime,
        ROW_NUMBER() OVER (PARTITION BY j.ServerId ORDER BY j.CaptureTime DESC) AS rn
    FROM fact.SqlJobRun AS j
    INNER JOIN dim.Server AS s ON s.ServerId = j.ServerId
    WHERE s.IsActive = 1
      AND (@Server IS NULL OR s.ServerName = @Server)
)
SELECT
    s.ServerName,
    la.AgentStatus,
    la.CaptureTime
FROM LatestAgent AS la
INNER JOIN dim.Server AS s ON s.ServerId = la.ServerId
WHERE la.rn = 1
ORDER BY s.ServerName;
";

        cmd.Parameters.Add(new SqlParameter("@Server", SqlDbType.NVarChar, 255)
        {
            Value = (object?)server ?? DBNull.Value
        });

        var reader = await cmd.ExecuteReaderAsync();
        var list = new List<object>();
        while (await reader.ReadAsync())
        {
            list.Add(new
            {
                serverName  = reader.GetString(0),
                agentStatus = reader.IsDBNull(1) ? null : reader.GetString(1),
                captureTime = reader.GetDateTime(2)
            });
        }

        return Results.Json(list);
    }
    catch (Exception ex)
    {
        return Results.Json(new
        {
            error = ex.Message,
            detail = ex.ToString()
        });
    }
});

// Helper function to resolve IP to hostname
static string ResolveServerName(string serverName)
{
    if (string.IsNullOrWhiteSpace(serverName))
        return serverName;
    
    // Check if it's an IP address
    if (System.Net.IPAddress.TryParse(serverName, out _))
    {
        try
        {
            var hostEntry = System.Net.Dns.GetHostEntry(serverName);
            if (!string.IsNullOrWhiteSpace(hostEntry.HostName))
            {
                // Extract short name from FQDN
                var shortName = hostEntry.HostName.Split('.')[0];
                return shortName;
            }
        }
        catch
        {
            // If DNS resolution fails, return original IP
        }
    }
    
    return serverName;
}

// ===== /api/firewall-status =====
app.MapGet("/api/firewall-status", async (HttpContext ctx) =>
{
    try
    {
        string? server = ctx.Request.Query["server"].ToString();
        if (string.IsNullOrWhiteSpace(server))
            server = null;

        using var conn = new SqlConnection(connString);
        await conn.OpenAsync();

        var cmd = conn.CreateCommand();
        cmd.CommandText = @"
WITH LatestFirewall AS (
    SELECT 
        f.ServerId,
        f.Profile,
        f.State,
        f.CaptureTime,
        ROW_NUMBER() OVER (PARTITION BY f.ServerId, f.Profile ORDER BY f.CaptureTime DESC) AS rn
    FROM fact.FirewallStatus AS f
    INNER JOIN dim.Server AS s ON s.ServerId = f.ServerId
    WHERE s.IsActive = 1
      AND (@Server IS NULL OR s.ServerName = @Server)
)
SELECT
    s.ServerName,
    lf.Profile,
    lf.State,
    lf.CaptureTime
FROM LatestFirewall AS lf
INNER JOIN dim.Server AS s ON s.ServerId = lf.ServerId
WHERE lf.rn = 1
ORDER BY s.ServerName, lf.Profile;
";

        cmd.Parameters.Add(new SqlParameter("@Server", SqlDbType.NVarChar, 255)
        {
            Value = (object?)server ?? DBNull.Value
        });

        var reader = await cmd.ExecuteReaderAsync();
        var list = new List<object>();
        while (await reader.ReadAsync())
        {
            var serverName = reader.GetString(0);
            var resolvedName = ResolveServerName(serverName);
            var profile = reader.GetString(1);
            var state = reader.GetString(2);
            
            list.Add(new
            {
                serverName  = resolvedName,
                profile     = profile,
                state       = state,
                captureTime = reader.GetDateTime(3)
            });
        }

        return Results.Json(list);
    }
    catch (Exception ex)
    {
        return Results.Json(new
        {
            error = ex.Message,
            detail = ex.ToString()
        });
    }
});

// ===== /api/dns-zones (DNS zone changes) =====
app.MapGet("/api/dns-zones", async (HttpContext ctx) =>
{
    var dateFromStr = ctx.Request.Query["dateFrom"].ToString();
    var dateToStr = ctx.Request.Query["dateTo"].ToString();
    var dateStr = ctx.Request.Query["date"].ToString();
    
    DateTime dateFrom, dateTo;
    
    if (!string.IsNullOrWhiteSpace(dateStr) && DateTime.TryParse(dateStr, out var singleDate))
    {
        dateFrom = singleDate.Date;
        dateTo = singleDate.Date.AddDays(1).AddSeconds(-1);
    }
    else if (!string.IsNullOrWhiteSpace(dateFromStr) && !string.IsNullOrWhiteSpace(dateToStr))
    {
        if (!DateTime.TryParse(dateFromStr, out dateFrom))
            dateFrom = DateTime.UtcNow.Date;
        if (!DateTime.TryParse(dateToStr, out dateTo))
            dateTo = DateTime.UtcNow.Date.AddDays(1).AddSeconds(-1);
        else
            dateTo = dateTo.Date.AddDays(1).AddSeconds(-1);
    }
    else
    {
        dateTo = DateTime.UtcNow;
        dateFrom = dateTo.AddDays(-1);
    }

    string? server = ctx.Request.Query["server"].ToString();
    if (string.IsNullOrWhiteSpace(server))
        server = null;

    using var conn = new SqlConnection(connString);
    await conn.OpenAsync();

    var cmd = conn.CreateCommand();
    cmd.CommandText = @"
SELECT TOP (500)
    z.EventTime,
    s.ServerName,
    z.ZoneName,
    z.Action,
    z.PerformedBy,
    z.Message
FROM fact.DnsZoneEvent AS z
JOIN dim.Server AS s ON s.ServerId = z.ServerId
WHERE z.EventTime >= @DateFrom AND z.EventTime <= @DateTo
  AND (@Server IS NULL OR s.ServerName = @Server)
ORDER BY z.EventTime DESC;
";

    cmd.Parameters.Add(new SqlParameter("@DateFrom", SqlDbType.DateTime2) { Value = dateFrom });
    cmd.Parameters.Add(new SqlParameter("@DateTo", SqlDbType.DateTime2) { Value = dateTo });
    cmd.Parameters.Add(new SqlParameter("@Server", SqlDbType.NVarChar, 255)
    {
        Value = (object?)server ?? DBNull.Value
    });

    var reader = await cmd.ExecuteReaderAsync();
    var list = new List<object>();
    while (await reader.ReadAsync())
    {
        var serverName = reader.GetString(1);
        var resolvedName = ResolveServerName(serverName);
        
        list.Add(new
        {
            time = reader.GetDateTime(0),
            server = resolvedName,
            zone = reader.IsDBNull(2) ? null : reader.GetString(2),
            zoneName = reader.IsDBNull(2) ? null : reader.GetString(2),
            action = reader.GetString(3),
            user = reader.IsDBNull(4) ? null : reader.GetString(4),
            performedBy = reader.IsDBNull(4) ? null : reader.GetString(4),
            message = reader.IsDBNull(5) ? null : reader.GetString(5)
        });
    }

    return Results.Json(list);
});

// ===== /api/dns-records (DNS record changes) =====
app.MapGet("/api/dns-records", async (HttpContext ctx) =>
{
    var dateFromStr = ctx.Request.Query["dateFrom"].ToString();
    var dateToStr = ctx.Request.Query["dateTo"].ToString();
    var dateStr = ctx.Request.Query["date"].ToString();
    
    DateTime dateFrom, dateTo;
    
    if (!string.IsNullOrWhiteSpace(dateStr) && DateTime.TryParse(dateStr, out var singleDate))
    {
        dateFrom = singleDate.Date;
        dateTo = singleDate.Date.AddDays(1).AddSeconds(-1);
    }
    else if (!string.IsNullOrWhiteSpace(dateFromStr) && !string.IsNullOrWhiteSpace(dateToStr))
    {
        if (!DateTime.TryParse(dateFromStr, out dateFrom))
            dateFrom = DateTime.UtcNow.Date;
        if (!DateTime.TryParse(dateToStr, out dateTo))
            dateTo = DateTime.UtcNow.Date.AddDays(1).AddSeconds(-1);
        else
            dateTo = dateTo.Date.AddDays(1).AddSeconds(-1);
    }
    else
    {
        dateTo = DateTime.UtcNow;
        dateFrom = dateTo.AddDays(-1);
    }

    string? server = ctx.Request.Query["server"].ToString();
    if (string.IsNullOrWhiteSpace(server))
        server = null;

    using var conn = new SqlConnection(connString);
    await conn.OpenAsync();

    var cmd = conn.CreateCommand();
    cmd.CommandText = @"
SELECT TOP (500)
    r.EventTime,
    s.ServerName,
    r.ZoneName,
    r.RecordName,
    r.RecordType,
    r.Action,
    r.PerformedBy,
    r.Message
FROM fact.DnsRecordEvent AS r
JOIN dim.Server AS s ON s.ServerId = r.ServerId
WHERE r.EventTime >= @DateFrom AND r.EventTime <= @DateTo
  AND (@Server IS NULL OR s.ServerName = @Server)
ORDER BY r.EventTime DESC;
";

    cmd.Parameters.Add(new SqlParameter("@DateFrom", SqlDbType.DateTime2) { Value = dateFrom });
    cmd.Parameters.Add(new SqlParameter("@DateTo", SqlDbType.DateTime2) { Value = dateTo });
    cmd.Parameters.Add(new SqlParameter("@Server", SqlDbType.NVarChar, 255)
    {
        Value = (object?)server ?? DBNull.Value
    });

    var reader = await cmd.ExecuteReaderAsync();
    var list = new List<object>();
    while (await reader.ReadAsync())
    {
        var serverName = reader.GetString(1);
        var resolvedName = ResolveServerName(serverName);
        
        list.Add(new
        {
            time = reader.GetDateTime(0),
            server = resolvedName,
            zone = reader.IsDBNull(2) ? null : reader.GetString(2),
            zoneName = reader.IsDBNull(2) ? null : reader.GetString(2),
            record = reader.IsDBNull(3) ? null : reader.GetString(3),
            recordName = reader.IsDBNull(3) ? null : reader.GetString(3),
            type = reader.IsDBNull(4) ? null : reader.GetString(4),
            operation = reader.IsDBNull(5) ? null : reader.GetString(5),
            action = reader.IsDBNull(5) ? null : reader.GetString(5),
            user = reader.IsDBNull(6) ? null : reader.GetString(6),
            performedBy = reader.IsDBNull(6) ? null : reader.GetString(6),
            message = reader.IsDBNull(7) ? null : reader.GetString(7)
        });
    }

    return Results.Json(list);
});

// ===== /api/ad-groups (Active Directory group changes) =====
app.MapGet("/api/ad-groups", async (HttpContext ctx) =>
{
    var dateFromStr = ctx.Request.Query["dateFrom"].ToString();
    var dateToStr = ctx.Request.Query["dateTo"].ToString();
    var dateStr = ctx.Request.Query["date"].ToString();
    
    DateTime dateFrom, dateTo;
    
    if (!string.IsNullOrWhiteSpace(dateStr) && DateTime.TryParse(dateStr, out var singleDate))
    {
        dateFrom = singleDate.Date;
        dateTo = singleDate.Date.AddDays(1).AddSeconds(-1);
    }
    else if (!string.IsNullOrWhiteSpace(dateFromStr) && !string.IsNullOrWhiteSpace(dateToStr))
    {
        if (!DateTime.TryParse(dateFromStr, out dateFrom))
            dateFrom = DateTime.UtcNow.Date;
        if (!DateTime.TryParse(dateToStr, out dateTo))
            dateTo = DateTime.UtcNow.Date.AddDays(1).AddSeconds(-1);
        else
            dateTo = dateTo.Date.AddDays(1).AddSeconds(-1);
    }
    else
    {
        dateTo = DateTime.UtcNow;
        dateFrom = dateTo.AddDays(-1);
    }

    string? server = ctx.Request.Query["server"].ToString();
    if (string.IsNullOrWhiteSpace(server))
        server = null;

    using var conn = new SqlConnection(connString);
    await conn.OpenAsync();

    var cmd = conn.CreateCommand();
    cmd.CommandText = @"
SELECT TOP (500)
    g.EventTime,
    s.ServerName,
    g.TargetGroup,
    g.MemberName,
    g.MemberType,
    g.Action,
    -- Return just username (like in DNS), prefer DisplayName, fallback to PerformedByRaw
    COALESCE(u.DisplayName, g.PerformedByRaw) AS PerformedBy,
    g.PerformedByRaw,
    g.PerformedByUserId
FROM fact.AdGroupEvent AS g
JOIN dim.Server AS s ON s.ServerId = g.DomainControllerId
LEFT JOIN [dim].[User] AS u ON u.UserId = g.PerformedByUserId
WHERE g.EventTime >= @DateFrom AND g.EventTime <= @DateTo
  AND (@Server IS NULL OR s.ServerName = @Server)
ORDER BY g.EventTime DESC;
";

    cmd.Parameters.Add(new SqlParameter("@DateFrom", SqlDbType.DateTime2) { Value = dateFrom });
    cmd.Parameters.Add(new SqlParameter("@DateTo", SqlDbType.DateTime2) { Value = dateTo });
    cmd.Parameters.Add(new SqlParameter("@Server", SqlDbType.NVarChar, 255)
    {
        Value = (object?)server ?? DBNull.Value
    });

    var reader = await cmd.ExecuteReaderAsync();
    var list = new List<object>();
    while (await reader.ReadAsync())
    {
        var dcName = reader.GetString(1);
        var resolvedDcName = ResolveServerName(dcName);
        
        list.Add(new
        {
            time = reader.GetDateTime(0),
            dc = resolvedDcName,
            group = reader.GetString(2),
            member = reader.GetString(3),
            memberType = reader.GetString(4),
            action = reader.GetString(5),
            by = reader.IsDBNull(6) ? null : reader.GetString(6),
            performedBy = reader.IsDBNull(6) ? null : reader.GetString(6), // Alias for compatibility
            performedByRaw = reader.IsDBNull(7) ? null : reader.GetString(7),
            performedByUserId = reader.IsDBNull(8) ? (int?)null : reader.GetInt32(8)
        });
    }

    return Results.Json(list);
});

// ===== /api/server-software (installed software and roles) =====
app.MapGet("/api/server-software", async (HttpContext ctx) =>
{
    try
    {
        string? server = ctx.Request.Query["server"].ToString();
        if (string.IsNullOrWhiteSpace(server))
            server = null;

        using var conn = new SqlConnection(connString);
        await conn.OpenAsync();

        var cmd = conn.CreateCommand();
        cmd.CommandText = @"
WITH LatestSoftware AS (
    SELECT 
        sw.ServerId,
        sw.OsVersion,
        sw.RolesJson,
        sw.SoftwareJson,
        sw.CaptureTime,
        ROW_NUMBER() OVER (PARTITION BY sw.ServerId ORDER BY sw.CaptureTime DESC) AS rn
    FROM fact.SoftwareAudit AS sw
    INNER JOIN dim.Server AS s ON s.ServerId = sw.ServerId
    WHERE s.IsActive = 1
      AND (@Server IS NULL OR s.ServerName = @Server)
)
SELECT
    s.ServerName,
    ls.OsVersion,
    ls.RolesJson,
    ls.SoftwareJson,
    ls.CaptureTime
FROM LatestSoftware AS ls
INNER JOIN dim.Server AS s ON s.ServerId = ls.ServerId
WHERE ls.rn = 1
ORDER BY s.ServerName;
";

        cmd.Parameters.Add(new SqlParameter("@Server", SqlDbType.NVarChar, 255)
        {
            Value = (object?)server ?? DBNull.Value
        });

        var reader = await cmd.ExecuteReaderAsync();
        var list = new List<object>();
        while (await reader.ReadAsync())
        {
            var serverName = reader.GetString(0);
            var resolvedName = ResolveServerName(serverName);
            var rolesJson = reader.IsDBNull(2) ? "[]" : reader.GetString(2);
            var softwareJson = reader.IsDBNull(3) ? "[]" : reader.GetString(3);
            
            list.Add(new
            {
                server = resolvedName,
                serverName = resolvedName,
                os = reader.IsDBNull(1) ? null : reader.GetString(1),
                roles = JsonSerializer.Deserialize<string[]>(rolesJson) ?? Array.Empty<string>(),
                software = JsonSerializer.Deserialize<string[]>(softwareJson) ?? Array.Empty<string>(),
                scanned = reader.GetDateTime(4)
            });
        }

        return Results.Json(list);
    }
    catch (Exception ex)
    {
        return Results.Json(new
        {
            error = ex.Message,
            detail = ex.ToString()
        });
    }
});

// ===== /api/ad-certificates (AD and LDAPS certificates) =====
app.MapGet("/api/ad-certificates", async (HttpContext ctx) =>
{
    try
    {
        string? server = ctx.Request.Query["server"].ToString();
        if (string.IsNullOrWhiteSpace(server))
            server = null;

        using var conn = new SqlConnection(connString);
        await conn.OpenAsync();

        var cmd = conn.CreateCommand();
        cmd.CommandText = @"
WITH LatestCerts AS (
    SELECT 
        c.ServerId,
        c.CertificateName,
        c.ExpirationDate,
        c.DaysRemaining,
        c.Severity,
        c.Thumbprint,
        c.CaptureTime,
        ROW_NUMBER() OVER (PARTITION BY c.ServerId, c.CertificateName ORDER BY c.CaptureTime DESC) AS rn
    FROM fact.AdCertificateStatus AS c
    INNER JOIN dim.Server AS s ON s.ServerId = c.ServerId
    WHERE s.IsActive = 1
      AND (@Server IS NULL OR s.ServerName = @Server)
)
SELECT
    s.ServerName,
    lc.CertificateName,
    lc.ExpirationDate,
    lc.DaysRemaining,
    lc.Severity,
    lc.Thumbprint
FROM LatestCerts AS lc
INNER JOIN dim.Server AS s ON s.ServerId = lc.ServerId
WHERE lc.rn = 1
ORDER BY lc.ExpirationDate ASC;
";

        cmd.Parameters.Add(new SqlParameter("@Server", SqlDbType.NVarChar, 255)
        {
            Value = (object?)server ?? DBNull.Value
        });

        var reader = await cmd.ExecuteReaderAsync();
        var list = new List<object>();
        while (await reader.ReadAsync())
        {
            var serverName = reader.GetString(0);
            var resolvedName = ResolveServerName(serverName);
            
            list.Add(new
            {
                server = resolvedName,
                cert = reader.GetString(1),
                expires = reader.GetDateTime(2),
                days = reader.GetInt32(3),
                severity = reader.GetString(4),
                level = reader.GetString(4), // Alias for compatibility
                thumbprint = reader.IsDBNull(5) ? null : reader.GetString(5)
            });
        }

        return Results.Json(list);
    }
    catch (Exception ex)
    {
        return Results.Json(new
        {
            error = ex.Message,
            detail = ex.ToString()
        });
    }
});

// ===== /api/web-server-certificates (web server certificates) =====
app.MapGet("/api/web-server-certificates", async (HttpContext ctx) =>
{
    try
    {
        using var conn = new SqlConnection(connString);
        await conn.OpenAsync();

        var cmd = conn.CreateCommand();
        cmd.CommandText = @"
WITH LatestCerts AS (
    SELECT 
        c.SiteName,
        c.Url,
        c.CertificateSubject,
        c.CertificateIssuer,
        c.ExpirationDate,
        c.DaysRemaining,
        c.Severity,
        c.Thumbprint,
        c.CaptureTime,
        ROW_NUMBER() OVER (PARTITION BY c.Url ORDER BY c.CaptureTime DESC) AS rn
    FROM fact.WebServerCertificate AS c
)
SELECT
    lc.SiteName,
    lc.Url,
    lc.CertificateSubject,
    lc.CertificateIssuer,
    lc.ExpirationDate,
    lc.DaysRemaining,
    lc.Severity,
    lc.Thumbprint
FROM LatestCerts AS lc
WHERE lc.rn = 1
ORDER BY lc.ExpirationDate ASC;
";

        var reader = await cmd.ExecuteReaderAsync();
        var list = new List<object>();
        while (await reader.ReadAsync())
        {
            list.Add(new
            {
                siteName = reader.GetString(0),
                url = reader.GetString(1),
                subject = reader.IsDBNull(2) ? null : reader.GetString(2),
                issuer = reader.IsDBNull(3) ? null : reader.GetString(3),
                expires = reader.GetDateTime(4),
                days = reader.GetInt32(5),
                severity = reader.GetString(6),
                thumbprint = reader.IsDBNull(7) ? null : reader.GetString(7)
            });
        }

        return Results.Json(list);
    }
    catch (Exception ex)
    {
        return Results.Json(new
        {
            error = ex.Message,
            detail = ex.ToString()
        });
    }
});

// ===== /api/group-policy-events (Group Policy changes) =====
app.MapGet("/api/group-policy-events", async (HttpContext ctx) =>
{
    try
    {
        var dateFromStr = ctx.Request.Query["dateFrom"].ToString();
        var dateToStr = ctx.Request.Query["dateTo"].ToString();
        var dateStr = ctx.Request.Query["date"].ToString();
        
        DateTime dateFrom, dateTo;
        
        if (!string.IsNullOrWhiteSpace(dateStr) && DateTime.TryParse(dateStr, out var singleDate))
        {
            dateFrom = singleDate.Date;
            dateTo = singleDate.Date.AddDays(1).AddSeconds(-1);
        }
        else if (!string.IsNullOrWhiteSpace(dateFromStr) && !string.IsNullOrWhiteSpace(dateToStr))
        {
            if (!DateTime.TryParse(dateFromStr, out dateFrom))
                dateFrom = DateTime.UtcNow.Date;
            if (!DateTime.TryParse(dateToStr, out dateTo))
                dateTo = DateTime.UtcNow.Date.AddDays(1).AddSeconds(-1);
            else
                dateTo = dateTo.Date.AddDays(1).AddSeconds(-1);
        }
        else
        {
            dateTo = DateTime.UtcNow;
            dateFrom = dateTo.AddDays(-1);
        }

        string? server = ctx.Request.Query["server"].ToString();
        if (string.IsNullOrWhiteSpace(server))
            server = null;

        using var conn = new SqlConnection(connString);
        await conn.OpenAsync();

        var cmd = conn.CreateCommand();
        cmd.CommandText = @"
SELECT TOP (500)
    g.EventTime,
    s.ServerName,
    g.GpoName,
    g.GpoGuid,
    g.Action,
    g.EventId,
    COALESCE(u.DisplayName, u.UPN, g.PerformedByRaw, '') AS PerformedBy,
    g.PerformedByRaw
FROM fact.GroupPolicyEvent AS g
INNER JOIN dim.Server AS s ON s.ServerId = g.DomainControllerId
LEFT JOIN [dim].[User] AS u ON u.UserId = g.PerformedByUserId
WHERE g.EventTime >= @DateFrom AND g.EventTime <= @DateTo
  AND (@Server IS NULL OR s.ServerName = @Server)
ORDER BY g.EventTime DESC;
";

        cmd.Parameters.Add(new SqlParameter("@DateFrom", SqlDbType.DateTime2) { Value = dateFrom });
        cmd.Parameters.Add(new SqlParameter("@DateTo", SqlDbType.DateTime2) { Value = dateTo });
        cmd.Parameters.Add(new SqlParameter("@Server", SqlDbType.NVarChar, 255)
        {
            Value = (object?)server ?? DBNull.Value
        });

        var reader = await cmd.ExecuteReaderAsync();
        var list = new List<object>();
        while (await reader.ReadAsync())
        {
            var serverName = reader.GetString(1);
            var resolvedName = ResolveServerName(serverName);
            
            list.Add(new
            {
                time = reader.GetDateTime(0),
                dc = resolvedName,
                gpoName = reader.GetString(2),
                gpoGuid = reader.IsDBNull(3) ? null : reader.GetString(3),
                action = reader.GetString(4),
                eventId = reader.GetInt32(5),
                by = reader.GetString(6),
                performedBy = reader.GetString(6)
            });
        }

        return Results.Json(list);
    }
    catch (Exception ex)
    {
        return Results.Json(new
        {
            error = ex.Message,
            detail = ex.ToString()
        });
    }
});

// ===== /api/backup-gcp-buckets (cloud backup validation) =====
app.MapGet("/api/backup-gcp-buckets", async (HttpContext ctx) =>
{
    try
    {
        var dateFromStr = ctx.Request.Query["dateFrom"].ToString();
        var dateToStr = ctx.Request.Query["dateTo"].ToString();
        var dateStr = ctx.Request.Query["date"].ToString();
        
        DateTime dateFrom, dateTo;
        
        if (!string.IsNullOrWhiteSpace(dateStr) && DateTime.TryParse(dateStr, out var singleDate))
        {
            dateFrom = singleDate.Date;
            dateTo = singleDate.Date.AddDays(1).AddSeconds(-1);
        }
        else if (!string.IsNullOrWhiteSpace(dateFromStr) && !string.IsNullOrWhiteSpace(dateToStr))
        {
            if (!DateTime.TryParse(dateFromStr, out dateFrom))
                dateFrom = DateTime.UtcNow.Date.AddDays(-7);
            if (!DateTime.TryParse(dateToStr, out dateTo))
                dateTo = DateTime.UtcNow.Date.AddDays(1).AddSeconds(-1);
            else
                dateTo = dateTo.Date.AddDays(1).AddSeconds(-1);
        }
        else
        {
            dateTo = DateTime.UtcNow;
            dateFrom = dateTo.AddDays(-7);
        }

        string? server = ctx.Request.Query["server"].ToString();
        if (string.IsNullOrWhiteSpace(server))
            server = null;

        using var conn = new SqlConnection(connString);
        await conn.OpenAsync();

        var cmd = conn.CreateCommand();
        cmd.CommandText = @"
SELECT TOP (500)
    b.ServerName,
    b.DatabaseName,
    b.BackupDate,
    b.BucketName,
    b.FileName,
    b.IsUploaded,
    b.FileSize,
    b.UploadedDate,
    b.GcpProjectId
FROM fact.BackupGcpBucket AS b
INNER JOIN dim.Server AS s ON s.ServerId = b.ServerId
WHERE b.BackupDate >= @DateFrom AND b.BackupDate <= @DateTo
  AND (@Server IS NULL OR b.ServerName = @Server)
ORDER BY b.BackupDate DESC, b.ServerName, b.DatabaseName;
";

        cmd.Parameters.Add(new SqlParameter("@DateFrom", SqlDbType.DateTime2) { Value = dateFrom });
        cmd.Parameters.Add(new SqlParameter("@DateTo", SqlDbType.DateTime2) { Value = dateTo });
        cmd.Parameters.Add(new SqlParameter("@Server", SqlDbType.NVarChar, 255)
        {
            Value = (object?)server ?? DBNull.Value
        });

        var reader = await cmd.ExecuteReaderAsync();
        var list = new List<object>();
        while (await reader.ReadAsync())
        {
            var serverName = reader.GetString(0);
            var resolvedName = ResolveServerName(serverName);
            
            list.Add(new
            {
                server = resolvedName,
                db = reader.GetString(1),
                databaseName = reader.GetString(1),
                backupDate = reader.GetDateTime(2),
                bucket = reader.GetString(3),
                file = reader.GetString(4),
                uploaded = reader.GetBoolean(5),
                fileSize = reader.IsDBNull(6) ? (long?)null : reader.GetInt64(6),
                uploadedDate = reader.IsDBNull(7) ? (DateTime?)null : reader.GetDateTime(7),
                projectId = reader.IsDBNull(8) ? null : reader.GetString(8)
            });
        }

        return Results.Json(list);
    }
    catch (Exception ex)
    {
        return Results.Json(new
        {
            error = ex.Message,
            detail = ex.ToString()
        });
    }
});

// ===== /api/ldap-users (LDAP user activity) =====
app.MapGet("/api/ldap-users", async (HttpContext ctx) =>
{
    var dateFromStr = ctx.Request.Query["dateFrom"].ToString();
    var dateToStr = ctx.Request.Query["dateTo"].ToString();
    var dateStr = ctx.Request.Query["date"].ToString();
    
    DateTime dateFrom, dateTo;
    
    if (!string.IsNullOrWhiteSpace(dateStr) && DateTime.TryParse(dateStr, out var singleDate))
    {
        dateFrom = singleDate.Date;
        dateTo = singleDate.Date.AddDays(1).AddSeconds(-1);
    }
    else if (!string.IsNullOrWhiteSpace(dateFromStr) && !string.IsNullOrWhiteSpace(dateToStr))
    {
        if (!DateTime.TryParse(dateFromStr, out dateFrom))
            dateFrom = DateTime.UtcNow.Date;
        if (!DateTime.TryParse(dateToStr, out dateTo))
            dateTo = DateTime.UtcNow.Date.AddDays(1).AddSeconds(-1);
        else
            dateTo = dateTo.Date.AddDays(1).AddSeconds(-1);
    }
    else
    {
        dateTo = DateTime.UtcNow;
        dateFrom = dateTo.AddDays(-1);
    }

    string? server = ctx.Request.Query["server"].ToString();
    if (string.IsNullOrWhiteSpace(server))
        server = null;

    try
    {
        using var conn = new SqlConnection(connString);
        await conn.OpenAsync();

        var cmd = conn.CreateCommand();
        cmd.CommandText = @"
SELECT DISTINCT
    CAST(l.LoginDate AS DATE) AS LoginDate,
    l.UserName,
    l.ClientIpAddress
FROM fact.LdapUserLogin AS l
JOIN dim.Server AS s ON s.ServerId = l.ServerId
WHERE l.LoginDate >= @DateFrom AND l.LoginDate <= @DateTo
  AND (@Server IS NULL OR s.ServerName = @Server)
ORDER BY CAST(l.LoginDate AS DATE) DESC, l.UserName;
";

        cmd.Parameters.Add(new SqlParameter("@DateFrom", SqlDbType.DateTime2) { Value = dateFrom });
        cmd.Parameters.Add(new SqlParameter("@DateTo", SqlDbType.DateTime2) { Value = dateTo });
        cmd.Parameters.Add(new SqlParameter("@Server", SqlDbType.NVarChar, 255)
        {
            Value = (object?)server ?? DBNull.Value
        });

        var reader = await cmd.ExecuteReaderAsync();
        var list = new List<object>();
        while (await reader.ReadAsync())
        {
            list.Add(new
            {
                date = reader.GetDateTime(0),
                user = reader.GetString(1),
                ip = reader.IsDBNull(2) ? "" : reader.GetString(2)
            });
        }

        return Results.Json(list);
    }
    catch (Exception ex)
    {
        return Results.Json(new
        {
            error = ex.Message,
            detail = ex.ToString()
        });
    }
});

// ===== /api/server-reboots (server reboot tracking) =====
app.MapGet("/api/server-reboots", async (HttpContext ctx) =>
{
    var dateFromStr = ctx.Request.Query["dateFrom"].ToString();
    var dateToStr = ctx.Request.Query["dateTo"].ToString();
    var dateStr = ctx.Request.Query["date"].ToString();
    
    DateTime dateFrom, dateTo;
    
    if (!string.IsNullOrWhiteSpace(dateStr) && DateTime.TryParse(dateStr, out var singleDate))
    {
        dateFrom = singleDate.Date;
        dateTo = singleDate.Date.AddDays(1).AddSeconds(-1);
    }
    else if (!string.IsNullOrWhiteSpace(dateFromStr) && !string.IsNullOrWhiteSpace(dateToStr))
    {
        if (!DateTime.TryParse(dateFromStr, out dateFrom))
            dateFrom = DateTime.UtcNow.Date.AddDays(-30);
        if (!DateTime.TryParse(dateToStr, out dateTo))
            dateTo = DateTime.UtcNow.Date.AddDays(1).AddSeconds(-1);
        else
            dateTo = dateTo.Date.AddDays(1).AddSeconds(-1);
    }
    else
    {
        // Default to the last 90 days while keeping date-only filters
        dateTo = DateTime.UtcNow.Date.AddDays(1).AddSeconds(-1);
        dateFrom = DateTime.UtcNow.Date.AddDays(-90);
    }

    string? server = ctx.Request.Query["server"].ToString();
    if (string.IsNullOrWhiteSpace(server))
        server = null;

    try
    {
        using var conn = new SqlConnection(connString);
        await conn.OpenAsync();

        var cmd = conn.CreateCommand();
        // Check whether the ShutdownTime column exists
        var checkColumnCmd = conn.CreateCommand();
        checkColumnCmd.CommandText = @"
            SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS 
            WHERE TABLE_SCHEMA = 'fact' 
            AND TABLE_NAME = 'ServerReboot' 
            AND COLUMN_NAME = 'ShutdownTime'
        ";
        var hasShutdownTime = (int)await checkColumnCmd.ExecuteScalarAsync() > 0;

        if (hasShutdownTime)
        {
            cmd.CommandText = @"
SELECT 
    s.ServerName AS server,
    r.BootTime AS boot,
    r.ShutdownTime AS [shutdown],
    r.Reason AS reason,
    COALESCE(u.DisplayName, u.UPN, r.InitiatedByRaw, '') AS [by]
FROM fact.ServerReboot AS r
JOIN dim.Server AS s ON s.ServerId = r.ServerId
LEFT JOIN dim.[User] AS u ON u.UserId = r.InitiatedByUserId
WHERE r.BootTime >= @DateFrom AND r.BootTime <= @DateTo
  AND (@Server IS NULL OR s.ServerName = @Server)
ORDER BY r.BootTime DESC;
";
        }
        else
        {
            // If ShutdownTime is unavailable, fall back to Reason or use NULL
            cmd.CommandText = @"
SELECT 
    s.ServerName AS server,
    r.BootTime AS boot,
    NULL AS [shutdown],
    r.Reason AS reason,
    COALESCE(u.DisplayName, u.UPN, r.InitiatedByRaw, '') AS [by]
FROM fact.ServerReboot AS r
JOIN dim.Server AS s ON s.ServerId = r.ServerId
LEFT JOIN dim.[User] AS u ON u.UserId = r.InitiatedByUserId
WHERE r.BootTime >= @DateFrom AND r.BootTime <= @DateTo
  AND (@Server IS NULL OR s.ServerName = @Server)
ORDER BY r.BootTime DESC;
";
        }

        cmd.Parameters.Add(new SqlParameter("@DateFrom", SqlDbType.DateTime2) { Value = dateFrom });
        cmd.Parameters.Add(new SqlParameter("@DateTo", SqlDbType.DateTime2) { Value = dateTo });
        cmd.Parameters.Add(new SqlParameter("@Server", SqlDbType.NVarChar, 255)
        {
            Value = (object?)server ?? DBNull.Value
        });

        var reader = await cmd.ExecuteReaderAsync();
        var list = new List<object>();
        while (await reader.ReadAsync())
        {
            list.Add(new
            {
                server = reader.GetString(0),
                boot = reader.GetDateTime(1),
                shutdown = reader.IsDBNull(2) ? (DateTime?)null : reader.GetDateTime(2),
                reason = reader.IsDBNull(3) ? "" : reader.GetString(3),
                by = reader.IsDBNull(4) ? "" : reader.GetString(4)
            });
        }

        return Results.Json(list);
    }
    catch (Exception ex)
    {
        return Results.Json(new
        {
            error = ex.Message,
            detail = ex.ToString()
        });
    }
});

// ===== /api/m365-unused-licenses (inactive Microsoft 365 users) =====
app.MapGet("/api/m365-unused-licenses", async (HttpContext ctx) =>
{
    try
    {
        using var conn = new SqlConnection(connString);
        await conn.OpenAsync();

        var cmd = conn.CreateCommand();
        cmd.CommandText = @"
SELECT TOP (500)
    DisplayName,
    UserPrincipalName,
    Email,
    LastActivity,
    DaysSinceLastActivity,
    Licenses,
    MonthlyCost
FROM fact.M365InactiveUser
WHERE SnapshotDate = (SELECT MAX(SnapshotDate) FROM fact.M365InactiveUser)
ORDER BY DaysSinceLastActivity DESC, MonthlyCost DESC;
";

        var reader = await cmd.ExecuteReaderAsync();
        var list = new List<object>();
        while (await reader.ReadAsync())
        {
            list.Add(new
            {
                displayName = reader.GetString(0),
                userPrincipalName = reader.GetString(1),
                email = reader.IsDBNull(2) ? "" : reader.GetString(2),
                lastActivity = reader.IsDBNull(3) ? (DateTime?)null : reader.GetDateTime(3),
                daysSinceLastActivity = reader.IsDBNull(4) ? (int?)null : reader.GetInt32(4),
                licenses = reader.IsDBNull(5) ? "" : reader.GetString(5),
                monthlyCost = reader.GetDecimal(6)
            });
        }

        return Results.Json(list);
    }
    catch (Exception ex)
    {
        return Results.Json(new
        {
            error = ex.Message,
            detail = ex.ToString()
        });
    }
});

// ===== /api/m365-license-cost-by-department (license cost by department) =====
app.MapGet("/api/m365-license-cost-by-department", async (HttpContext ctx) =>
{
    try
    {
        using var conn = new SqlConnection(connString);
        await conn.OpenAsync();

        var cmd = conn.CreateCommand();
        cmd.CommandText = @"
SELECT 
    Department,
    TotalCost,
    ENTERPRISEPACK,
    F1,
    F1_FIRSTLINE,
    M365_F1,
    M365_F1_COMM,
    MICROSOFT_365_F1,
    O365_BUSINESS,
    O365_BUSINESS_ESSENTIALS,
    O365_BUSINESS_PREMIUM,
    O365_F1,
    O365_STANDARD,
    OFFICE_365_F1,
    OFFICESUBSCRIPTION,
    POWER_BI_PREMIUM_PER_USER,
    POWER_BI_PRO,
    SPB,
    SPE_F1,
    STANDARDPACK,
    TEAMS_ESSENTIALS,
    TEAMS_PREMIUM,
    ISNULL(M365_COPILOT, 0) AS M365_COPILOT,
    ISNULL(COPILOT_STANDARD, 0) AS COPILOT_STANDARD,
    ISNULL(Microsoft_365_Copilot, 0) AS Microsoft_365_Copilot
FROM fact.M365LicenseCostByDepartment
WHERE SnapshotDate = (SELECT MAX(SnapshotDate) FROM fact.M365LicenseCostByDepartment)
ORDER BY TotalCost DESC;
";

        var reader = await cmd.ExecuteReaderAsync();
        var list = new List<object>();
        while (await reader.ReadAsync())
        {
            list.Add(new
            {
                department = reader.GetString(0),
                totalCost = reader.GetDecimal(1),
                enterprisepack = reader.GetInt32(2),
                f1 = reader.GetInt32(3),
                f1_firstline = reader.GetInt32(4),
                m365_f1 = reader.GetInt32(5),
                m365_f1_comm = reader.GetInt32(6),
                microsoft_365_f1 = reader.GetInt32(7),
                o365_business = reader.GetInt32(8),
                o365_business_essentials = reader.GetInt32(9),
                o365_business_premium = reader.GetInt32(10),
                o365_f1 = reader.GetInt32(11),
                o365_standard = reader.GetInt32(12),
                office_365_f1 = reader.GetInt32(13),
                officesubscription = reader.GetInt32(14),
                power_bi_premium_per_user = reader.GetInt32(15),
                power_bi_pro = reader.GetInt32(16),
                spb = reader.GetInt32(17),
                spe_f1 = reader.GetInt32(18),
                standardpack = reader.GetInt32(19),
                teams_essentials = reader.GetInt32(20),
                teams_premium = reader.GetInt32(21),
                m365_copilot = reader.GetInt32(22),
                copilot_standard = reader.GetInt32(23),
                microsoft_365_copilot = reader.GetInt32(24)
            });
        }

        return Results.Json(list);
    }
    catch (Exception ex)
    {
        return Results.Json(new
        {
            error = ex.Message,
            detail = ex.ToString()
        });
    }
});

app.Run();

