# Sanitized sample from an internal infrastructure monitoring project.
# Secrets, internal identifiers, and localized text have been removed or generalized.

# Script for checking SSL certificates on web servers
# Writes results to Monitoring database

param(
    [string]$ConnectionString = "Server=<SQL_SERVER>;Database=<MONITORING_DATABASE>;User ID=<SQL_USERNAME>;Password=<SQL_PASSWORD>;TrustServerCertificate=True;"
)

$webSites = @(
    @{
        Name = "Public Application Endpoint"
        Url = "https://app.example.com/"
    },
    @{
        Name = "Reporting Portal Endpoint"
        Url = "https://reports.example.com/"
    },
    @{
        Name = "Internal Service Endpoint"
        Url = "https://<INTERNAL_ENDPOINT>/"
    },
    @{
        Name = "Internal Management Endpoint"
        Url = "https://mgmt.internal.example:8443/"
    }
)

function Get-WebServerCertificate {
    param(
        [string]$Url
    )
    
    $originalCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
    
    try {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {
            param($snd, $certificate, $chain, $sslPolicyErrors)
            return $true
        }
        
        $uri = [System.Uri]$Url
        $port = if ($uri.Port -ne -1) { $uri.Port } else { if ($uri.Scheme -eq "https") { 443 } else { 80 } }
        
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.ReceiveTimeout = 10000
        $tcpClient.SendTimeout = 10000
        
        try {
            $tcpClient.Connect($uri.Host, $port)
            
            if (-not $tcpClient.Connected) {
                Write-Warning "Sanitized status message"
                $tcpClient.Close()
                return $null
            }
            
            $sslStream = New-Object System.Net.Security.SslStream(
                $tcpClient.GetStream(),
                $false,
                {
                    param($snd, $certificate, $chain, $sslPolicyErrors)
                    return $true
                },
                $null
            )
            
            $sslStream.ReadTimeout = 10000
            $sslStream.WriteTimeout = 10000
            
            $authenticated = $false
            $cert = $null
            
            $protocols = @(
                [System.Security.Authentication.SslProtocols]::Tls13,
                [System.Security.Authentication.SslProtocols]::Tls12,
                [System.Security.Authentication.SslProtocols]::Tls11,
                [System.Security.Authentication.SslProtocols]::Tls
            )
            
            foreach ($protocol in $protocols) {
                try {
                    $sslStream.AuthenticateAsClient($uri.Host, $null, $protocol, $false)
                    $authenticated = $true
                    break
                }
                catch {
                    continue
                }
            }
            
            if (-not $authenticated) {
                try {
                    $sslStream.AuthenticateAsClient($uri.Host)
                    $authenticated = $true
                }
                catch {
                    Write-Warning "Sanitized status message"
                }
            }
            
            if ($authenticated) {
                $certificate = $sslStream.RemoteCertificate
                if ($certificate) {
                    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certificate)
                }
            }
            
            $sslStream.Close()
            $tcpClient.Close()
            
            return $cert
        }
        catch {
            if ($tcpClient.Connected) {
                try {
                    $tcpClient.Close()
                }
                catch {
                }
            }
            Write-Warning "Sanitized status message"
            return $null
        }
    }
    catch {
        Write-Warning "Sanitized status message"
        return $null
    }
    finally {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $originalCallback
    }
}

function Get-Severity {
    param([int]$DaysRemaining)
    
    if ($DaysRemaining -le 30) {
        return "red"
    }
    elseif ($DaysRemaining -le 60) {
        return "yellow"
    }
    else {
        return "green"
    }
}

try {
    $connection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
    $connection.Open()
    Write-Host "Sanitized status message" -ForegroundColor Green
}
catch {
    Write-Error "Sanitized status message"
    exit 1
}

$snapshotDate = Get-Date -Format "yyyy-MM-dd"
$currentDate = Get-Date

$deleteQuery = @"
    DELETE FROM fact.WebServerCertificate 
    WHERE CAST(CaptureTime AS DATE) = CAST(GETDATE() AS DATE)
"@
$deleteCmd = New-Object System.Data.SqlClient.SqlCommand($deleteQuery, $connection)
$deletedRows = $deleteCmd.ExecuteNonQuery()
Write-Host "Sanitized status message" -ForegroundColor Yellow

$insertQuery = @"
    INSERT INTO fact.WebServerCertificate (
        SiteName,
        Url,
        CertificateSubject,
        CertificateIssuer,
        ExpirationDate,
        DaysRemaining,
        Severity,
        Thumbprint,
        CaptureTime,
        Source
    )
    VALUES (
        @SiteName,
        @Url,
        @CertificateSubject,
        @CertificateIssuer,
        @ExpirationDate,
        @DaysRemaining,
        @Severity,
        @Thumbprint,
        @CaptureTime,
        @Source
    )
"@

$insertCmd = New-Object System.Data.SqlClient.SqlCommand($insertQuery, $connection)
$insertedCount = 0

Write-Host "Sanitized status message" -ForegroundColor Cyan

foreach ($site in $webSites) {
    $siteName = $site.Name
    $url = $site.Url
    
    Write-Host "Sanitized status message" -ForegroundColor Yellow
    
    $cert = Get-WebServerCertificate -Url $url
    
    if ($cert) {
        $expirationDate = $cert.NotAfter
        $daysRemaining = [Math]::Floor(($expirationDate - $currentDate).TotalDays)
        $severity = Get-Severity -DaysRemaining $daysRemaining
        
        Write-Host "Sanitized status message" -ForegroundColor Green
        Write-Host "  Subject: $($cert.Subject)" -ForegroundColor Gray
        Write-Host "  Issuer: $($cert.Issuer)" -ForegroundColor Gray
        Write-Host "  Expires: $($expirationDate.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
        Write-Host "  Days remaining: $daysRemaining" -ForegroundColor $(if ($severity -eq "red") { "Red" } elseif ($severity -eq "yellow") { "Yellow" } else { "Green" })
        
        $insertCmd.Parameters.Clear()
        $insertCmd.Parameters.AddWithValue("@SiteName", $siteName) | Out-Null
        $insertCmd.Parameters.AddWithValue("@Url", $url) | Out-Null
        
        if ($cert.Subject) {
            $insertCmd.Parameters.AddWithValue("@CertificateSubject", $cert.Subject) | Out-Null
        } else {
            $insertCmd.Parameters.AddWithValue("@CertificateSubject", [DBNull]::Value) | Out-Null
        }
        
        if ($cert.Issuer) {
            $insertCmd.Parameters.AddWithValue("@CertificateIssuer", $cert.Issuer) | Out-Null
        } else {
            $insertCmd.Parameters.AddWithValue("@CertificateIssuer", [DBNull]::Value) | Out-Null
        }
        
        $insertCmd.Parameters.AddWithValue("@ExpirationDate", $expirationDate) | Out-Null
        $insertCmd.Parameters.AddWithValue("@DaysRemaining", $daysRemaining) | Out-Null
        $insertCmd.Parameters.AddWithValue("@Severity", $severity) | Out-Null
        
        if ($cert.Thumbprint) {
            $insertCmd.Parameters.AddWithValue("@Thumbprint", $cert.Thumbprint) | Out-Null
        } else {
            $insertCmd.Parameters.AddWithValue("@Thumbprint", [DBNull]::Value) | Out-Null
        }
        
        $insertCmd.Parameters.AddWithValue("@CaptureTime", $currentDate) | Out-Null
        $insertCmd.Parameters.AddWithValue("@Source", "Check-WebServerCertificates") | Out-Null
        
        try {
            $insertCmd.ExecuteNonQuery() | Out-Null
            $insertedCount++
            Write-Host "Sanitized status message" -ForegroundColor Green
        }
        catch {
            Write-Warning "Sanitized status message"
        }
    }
    else {
        Write-Warning "Sanitized status message"
    }
}

$connection.Close()

Write-Host "Sanitized status message" -ForegroundColor Cyan
Write-Host "Sanitized status message" -ForegroundColor Green
Write-Host "Sanitized status message" -ForegroundColor Green
Write-Host "Sanitized status message" -ForegroundColor Green

