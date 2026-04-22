# Sanitized sample from an internal infrastructure monitoring project.
# Secrets, internal identifiers, and localized text have been removed or generalized.

# Script for checking AD/LDAPS certificates on Domain Controllers
# Writes results to Monitoring database

param(
    [string]$ConnectionString = "Server=<SQL_SERVER>;Database=<MONITORING_DATABASE>;User ID=<SQL_USERNAME>;Password=<SQL_PASSWORD>;TrustServerCertificate=True;",
    [string[]]$DomainControllers = @(),
    [switch]$UseDefaultControllers = $false
)

Import-Module ActiveDirectory -ErrorAction SilentlyContinue

# Default list of Domain Controllers
$defaultDomainControllers = @(
    "<DOMAIN_CONTROLLER>",
    "<DOMAIN_CONTROLLER>",
    "<DOMAIN_CONTROLLER>",
    "<DOMAIN_CONTROLLER>",
    "<DOMAIN_CONTROLLER>",
    "<DOMAIN_CONTROLLER>",
    "<DOMAIN_CONTROLLER>"
)

# Certificate store paths to check
$certStorePaths = @(
    "Cert:\LocalMachine\My",      # Personal
    "Cert:\LocalMachine\Root"     # Trusted Root Certification Authorities
)

# Function to get list of DCs from database
function Get-DomainControllersFromDatabase {
    param([string]$ConnString)
    
    try {
        $query = @"
            SELECT DISTINCT s.ServerId, s.ServerName 
            FROM dim.Server AS s
            WHERE s.IsActive = 1
              AND (s.Role LIKE '%DC%' OR s.Role LIKE '%Domain Controller%')
            ORDER BY s.ServerName
"@
        
        $connection = New-Object System.Data.SqlClient.SqlConnection($ConnString)
        $command = New-Object System.Data.SqlClient.SqlCommand($query, $connection)
        $connection.Open()
        
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($command)
        $dataset = New-Object System.Data.DataSet
        $adapter.Fill($dataset) | Out-Null
        
        $servers = @()
        foreach ($row in $dataset.Tables[0].Rows) {
            $servers = $servers + [PSCustomObject]@{
                ServerId = [int]$row["ServerId"]
                ServerName = [string]$row["ServerName"]
            }
        }
        
        $connection.Close()
        return $servers
    }
    catch {
        Write-Warning "Error getting DCs from database: $_"
        return @()
    }
}

# Function to get DCs from Active Directory
function Get-DomainControllersFromAD {
    try {
        $dcs = Get-ADDomainController -Filter * | Select-Object -ExpandProperty HostName
        $servers = @()
        foreach ($dc in $dcs) {
            # Extract short name from FQDN
            $shortName = $dc -replace '\..*$', ''
            $servers = $servers + [PSCustomObject]@{
                ServerId = 0
                ServerName = $shortName
            }
        }
        return $servers
    }
    catch {
        Write-Warning "Error getting DCs from AD: $_"
        return @()
    }
}

# Function to get or create server in database
function Get-OrCreateServer {
    param(
        [string]$ServerName,
        [string]$ConnString
    )
    
    try {
        # First, try to find existing server
        $query = "SELECT ServerId FROM dim.Server WHERE ServerName = @ServerName"
        $connection = New-Object System.Data.SqlClient.SqlConnection($ConnString)
        $command = New-Object System.Data.SqlClient.SqlCommand($query, $connection)
        $command.Parameters.AddWithValue("@ServerName", $ServerName) | Out-Null
        $connection.Open()
        
        $result = $command.ExecuteScalar()
        $connection.Close()
        
        if ($result -ne $null) {
            return [int]$result
        }
        
        # Server not found, create it
        $insertQuery = @"
            INSERT INTO dim.Server (ServerName, IsActive, Role, CreatedAt)
            VALUES (@ServerName, 1, 'Domain Controller', GETDATE());
            SELECT CAST(SCOPE_IDENTITY() AS INT);
"@
        
        $connection = New-Object System.Data.SqlClient.SqlConnection($ConnString)
        $command = New-Object System.Data.SqlClient.SqlCommand($insertQuery, $connection)
        $command.Parameters.AddWithValue("@ServerName", $ServerName) | Out-Null
        $connection.Open()
        
        $newId = [int]$command.ExecuteScalar()
        $connection.Close()
        
        Write-Host "Created server entry: $ServerName (ID: $newId)" -ForegroundColor Green
        return $newId
    }
    catch {
        Write-Warning "Error getting/creating server $ServerName : $_"
        return 0
    }
}

# Function to get certificates from a server
function Get-CertificatesFromServer {
    param(
        [string]$ServerName,
        [string[]]$StorePaths
    )
    
    $certificates = @()
    
    foreach ($storePath in $StorePaths) {
        try {
            $storeName = if ($storePath -like "*\My") { "Personal" } 
                        elseif ($storePath -like "*\Root") { "Trusted Root Certification Authorities" }
                        else { "Unknown" }
            
            Write-Host "  Checking store: $storeName ($storePath)" -ForegroundColor Gray
            
            $certs = Invoke-Command -ComputerName $ServerName -ScriptBlock {
                param ($path)
                Get-ChildItem -Path $path -ErrorAction SilentlyContinue
            } -ArgumentList $storePath -ErrorAction SilentlyContinue
            
            if ($certs) {
                Write-Host "    Found $($certs.Count) certificate(s) in $storeName" -ForegroundColor Gray
                $filteredCount = 0
                foreach ($cert in $certs) {
                    $currentDate = Get-Date
                    $expirationDate = $cert.NotAfter
                    $daysRemaining = ($expirationDate - $currentDate).Days
                    
                    if ($daysRemaining -lt 0) {
                        $filteredCount++
                        continue
                    }
                    
                    if ($cert.Subject -like "*Microsoft Time Stamping Service Root*" -and $expirationDate -lt (Get-Date).AddYears(-10)) {
                        $filteredCount++
                        continue
                    }
                    
                    # Determine severity
                    $severity = "green"
                    if ($daysRemaining -le 30) {
                        $severity = "red"
                    }
                    elseif ($daysRemaining -le 60) {
                        $severity = "yellow"
                    }
                    
                    $certificates = $certificates + [PSCustomObject]@{
                        CertificateName = [string]$cert.Subject
                        ExpirationDate = [DateTime]$expirationDate
                        DaysRemaining = [int]$daysRemaining
                        Severity = [string]$severity
                        Thumbprint = if ($cert.Thumbprint) { [string]$cert.Thumbprint } else { $null }
                        StoreName = $storeName
                    }
                }
                if ($filteredCount -gt 0) {
                    Write-Host "    Filtered out $filteredCount expired/old certificate(s)" -ForegroundColor Gray
                }
            }
            else {
                Write-Host "    No certificates found in $storeName" -ForegroundColor Gray
            }
        }
        catch {
            Write-Warning "Error getting certificates from $ServerName ($storePath): $_"
        }
    }
    
    return $certificates
}

# Function to clear old certificate data before inserting new
function Clear-OldCertificates {
    param(
        [string]$ConnString
    )
    
    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection($ConnString)
        $connection.Open()
        
        $deleteQuery = "DELETE FROM fact.AdCertificateStatus;"
        $deleteCmd = New-Object System.Data.SqlClient.SqlCommand($deleteQuery, $connection)
        $deleted = $deleteCmd.ExecuteNonQuery()
        
        $connection.Close()
        Write-Host "Cleared $deleted old certificate record(s) from database" -ForegroundColor Yellow
        return $true
    }
    catch {
        Write-Warning "Error clearing old certificates: $_"
        return $false
    }
}

# Function to write certificates to database
function Write-CertificatesToDatabase {
    param(
        [array]$Certificates,
        [int]$ServerId,
        [string]$ConnString
    )
    
    if ($Certificates.Count -eq 0) {
        return
    }
    
    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection($ConnString)
        $connection.Open()
        
        $insertQuery = @"
            INSERT INTO fact.AdCertificateStatus 
                (CaptureTime, ServerId, CertificateName, ExpirationDate, DaysRemaining, Severity, Thumbprint)
            VALUES 
                (@CaptureTime, @ServerId, @CertificateName, @ExpirationDate, @DaysRemaining, @Severity, @Thumbprint);
"@
        
        $insertCmd = New-Object System.Data.SqlClient.SqlCommand($insertQuery, $connection)
        $insertCmd.Parameters.Add("@CaptureTime", [System.Data.SqlDbType]::DateTime2) | Out-Null
        $insertCmd.Parameters.Add("@ServerId", [System.Data.SqlDbType]::Int) | Out-Null
        $insertCmd.Parameters.Add("@CertificateName", [System.Data.SqlDbType]::NVarChar, 512) | Out-Null
        $insertCmd.Parameters.Add("@ExpirationDate", [System.Data.SqlDbType]::DateTime2) | Out-Null
        $insertCmd.Parameters.Add("@DaysRemaining", [System.Data.SqlDbType]::Int) | Out-Null
        $insertCmd.Parameters.Add("@Severity", [System.Data.SqlDbType]::NVarChar, 20) | Out-Null
        $insertCmd.Parameters.Add("@Thumbprint", [System.Data.SqlDbType]::NVarChar, 100) | Out-Null
        
        $captureTime = Get-Date
        $inserted = 0
        
        foreach ($cert in $Certificates) {
            $insertCmd.Parameters["@CaptureTime"].Value = $captureTime
            $insertCmd.Parameters["@ServerId"].Value = $ServerId
            $insertCmd.Parameters["@CertificateName"].Value = $cert.CertificateName
            $insertCmd.Parameters["@ExpirationDate"].Value = $cert.ExpirationDate
            $insertCmd.Parameters["@DaysRemaining"].Value = $cert.DaysRemaining
            $insertCmd.Parameters["@Severity"].Value = $cert.Severity
            if ($cert.Thumbprint) {
                $insertCmd.Parameters["@Thumbprint"].Value = $cert.Thumbprint
            }
            else {
                $insertCmd.Parameters["@Thumbprint"].Value = [DBNull]::Value
            }
            
            try {
                $insertCmd.ExecuteNonQuery() | Out-Null
                $inserted++
            }
            catch {
                Write-Warning "Error inserting certificate $($cert.CertificateName): $_"
            }
        }
        
        $connection.Close()
        Write-Host "Inserted $inserted certificates for server ID $ServerId" -ForegroundColor Green
    }
    catch {
        Write-Error "Error writing certificates to database: $_"
    }
}

# Main execution
Write-Host "Getting list of Domain Controllers..." -ForegroundColor Cyan

$servers = @()

if ($DomainControllers.Count -gt 0) {
    Write-Host "Using provided DC list: $($DomainControllers -join ', ')" -ForegroundColor Yellow
    foreach ($dc in $DomainControllers) {
        $servers = $servers + [PSCustomObject]@{
            ServerId = 0
            ServerName = $dc
        }
    }
}
elseif ($UseDefaultControllers) {
    Write-Host "Using default DC list" -ForegroundColor Yellow
    foreach ($dc in $defaultDomainControllers) {
        $servers = $servers + [PSCustomObject]@{
            ServerId = 0
            ServerName = $dc
        }
    }
}
else {
    Write-Host "Using default DC list (<DOMAIN_CONTROLLER>, <DOMAIN_CONTROLLER>, <DOMAIN_CONTROLLER>, <DOMAIN_CONTROLLER>, <DOMAIN_CONTROLLER>, <DOMAIN_CONTROLLER>, <DOMAIN_CONTROLLER>)" -ForegroundColor Yellow
    foreach ($dc in $defaultDomainControllers) {
        $servers = $servers + [PSCustomObject]@{
            ServerId = 0
            ServerName = $dc
        }
    }
    
    # Write-Host "Getting DCs from database..." -ForegroundColor Cyan
    # $servers = Get-DomainControllersFromDatabase -ConnString $ConnectionString
    # 
    # if ($servers.Count -eq 0) {
    #     Write-Host "No DCs found in database, trying Active Directory..." -ForegroundColor Yellow
    #     $servers = Get-DomainControllersFromAD
    # }
    # 
    # if ($servers.Count -eq 0) {
    #     Write-Host "No DCs found, falling back to default list..." -ForegroundColor Yellow
    #     foreach ($dc in $defaultDomainControllers) {
    #         $servers = $servers + [PSCustomObject]@{
    #             ServerId = 0
    #             ServerName = $dc
    #         }
    #     }
    # }
}

if ($servers.Count -eq 0) {
    Write-Error "No Domain Controllers found. Exiting."
    exit 1
}

Write-Host "Found $($servers.Count) Domain Controllers" -ForegroundColor Green
Write-Host "Checking certificates..." -ForegroundColor Cyan

$allCertificates = @()

foreach ($server in $servers) {
    $serverName = $server.ServerName
    Write-Host "Checking DC: $serverName..." -ForegroundColor Cyan
    
    # Get or create server in database
    $serverId = $server.ServerId
    if ($serverId -eq 0) {
        $serverId = Get-OrCreateServer -ServerName $serverName -ConnString $ConnectionString
        if ($serverId -eq 0) {
            Write-Warning "Could not get/create server $serverName, skipping..."
            continue
        }
    }
    
    # Check if server is reachable
    if (-not (Test-Connection -ComputerName $serverName -Count 1 -Quiet)) {
        Write-Warning "Server $serverName is unavailable (ping failed) - Skipping"
        continue
    }
    
    # Get certificates
    $certs = Get-CertificatesFromServer -ServerName $serverName -StorePaths $certStorePaths
    
    if ($certs.Count -gt 0) {
        Write-Host "  Found $($certs.Count) certificates" -ForegroundColor Green
        foreach ($cert in $certs) {
            $cert | Add-Member -MemberType NoteProperty -Name "ServerId" -Value $serverId
            $cert | Add-Member -MemberType NoteProperty -Name "ServerName" -Value $serverName
        }
        $allCertificates = $allCertificates + $certs
    }
    else {
        Write-Host "  No certificates found" -ForegroundColor Yellow
    }
}

Write-Host "`n=== Results ===" -ForegroundColor Cyan
Write-Host "DCs checked: $($servers.Count)" -ForegroundColor Green
Write-Host "Total certificates: $($allCertificates.Count)" -ForegroundColor Green

if ($allCertificates.Count -gt 0) {
    Write-Host "Writing results to database..." -ForegroundColor Cyan
    
    # Clear old certificate data before inserting new
    Write-Host "Clearing old certificate data..." -ForegroundColor Yellow
    Clear-OldCertificates -ConnString $ConnectionString
    
    # Group by server
    $byServer = $allCertificates | Group-Object -Property ServerId
    
    foreach ($group in $byServer) {
        Write-CertificatesToDatabase -Certificates $group.Group -ServerId $group.Name -ConnString $ConnectionString
    }
}

Write-Host "=== Done ===" -ForegroundColor Green

