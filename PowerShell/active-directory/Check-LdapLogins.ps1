# Sanitized sample from an internal infrastructure monitoring project.
# Secrets, internal identifiers, and localized text have been removed or generalized.

# Script for checking LDAP (non-LDAPS) connections of domain users to services/servers
# Events are logged on Domain Controllers when clients (e.g., mail server, applications) 
# connect to DC via LDAP (not LDAPS) to authenticate domain users
# Writes results to Monitoring database
# Based on Monitor-LDAP-all.ps1 but writes to database instead of files

param(
    [string]$ConnectionString = "Server=<SQL_SERVER>;Database=<MONITORING_DATABASE>;User ID=<SQL_USERNAME>;Password=<SQL_PASSWORD>;TrustServerCertificate=True;",
    [string[]]$DomainControllers = @(),
    [switch]$UseDefaultControllers = $false,
    [int]$DaysBack = 1
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

# Event IDs for LDAP (non-LDAPS) connections
# 2889 - LDAP simple bind (non-SSL) - client (e.g., mail server, app) connects to DC via LDAP to authenticate domain user
# 3039 - LDAP bind over SSL failed, falling back to simple bind
# 3074 - LDAP bind over SSL failed
# 3075 - LDAP bind over SSL succeeded (we want to exclude this - only non-LDAPS)
# These events are logged on DC when external services (mail server, apps) authenticate domain users via LDAP
$ldapEventIds = @(2889, 3039, 3074)  # Exclude 3075 (LDAPS success)

# Function to get list of DCs from database
function Get-DomainControllersFromDatabase {
    param([string]$ConnString)
    
    try {
        $query = @"
            SELECT DISTINCT s.ServerId, s.ServerName 
            FROM dim.Server AS s
            WHERE s.IsActive = 1
              AND (s.Role LIKE '%DC%' OR s.Role LIKE '%Domain Controller%' OR s.ServerName LIKE 'DC%' OR s.ServerName LIKE 'dc%')
            ORDER BY s.ServerName
"@
        
        $connection = New-Object System.Data.SqlClient.SqlConnection($ConnString)
        $command = New-Object System.Data.SqlClient.SqlCommand($query, $connection)
        $connection.Open()
        
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($command)
        $dataset = New-Object System.Data.DataSet
        $adapter.Fill($dataset) | Out-Null
        
        $servers = @()
        if ($dataset.Tables.Count -gt 0 -and $dataset.Tables[0].Rows.Count -gt 0) {
            foreach ($row in $dataset.Tables[0].Rows) {
                $servers = $servers + [PSCustomObject]@{
                    ServerId = [int]$row["ServerId"]
                    ServerName = [string]$row["ServerName"]
                }
            }
            Write-Host "Found $($servers.Count) DCs in database" -ForegroundColor Green
        }
        else {
            Write-Host "No DCs found in database" -ForegroundColor Yellow
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
        Write-Host "Searching for DCs in Active Directory..." -ForegroundColor Cyan
        $dcs = Get-ADDomainController -Filter * | Select-Object -ExpandProperty HostName
        $servers = @()
        foreach ($dc in $dcs) {
            # Keep FQDN for Invoke-Command (as in original script)
            # Extract short name for display and database
            $shortName = $dc -replace '\..*$', ''
            $servers = $servers + [PSCustomObject]@{
                ServerId = 0
                ServerName = $shortName
                FQDN = $dc  # Keep FQDN for remote access
            }
        }
        Write-Host "Found $($servers.Count) DCs in Active Directory" -ForegroundColor Green
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

# Function to get LDAP login events from a server
# Uses the same logic as the original script - queries each EventID separately with FQDN
function Get-LdapLoginEventsFromServer {
    param(
        [string]$ServerName,
        [string]$ServerFQDN,
        [int[]]$EventIds,
        [DateTime]$StartTime
    )
    
    $allParsedEvents = @()
    
    # Use FQDN for Invoke-Command if provided (as in original script), otherwise use ServerName
    $targetServer = if ($ServerFQDN) { $ServerFQDN } else { $ServerName }
    
    try {
        Write-Host "  Querying events from Directory Service log (IDs: $($EventIds -join ', '))..." -ForegroundColor Gray
        Write-Host "    Start time: $StartTime" -ForegroundColor DarkGray
        
        # Query each EventID separately (as in original script)
        foreach ($EventID in $EventIds) {
            try {
                $winEvents = Invoke-Command -ComputerName $targetServer -ScriptBlock {
                    param($EventID, $StartTime)
                    Get-WinEvent -FilterHashtable @{
                        LogName   = 'Directory Service'
                        Id        = $EventID
                        StartTime = $StartTime
                    } -ErrorAction SilentlyContinue
                } -ArgumentList $EventID, $StartTime -ErrorAction SilentlyContinue
                
                if ($winEvents) {
                    Write-Host "    Found $($winEvents.Count) events with ID $EventID" -ForegroundColor DarkGray
                    
                    # Parse each event
                    foreach ($event in $winEvents) {
                        # Extract user name and IP from event message
                        # Format: "The following client performed a SASL (Negotiate/Kerberos/NTLM/Digest) LDAP bind without requesting signing (integrity verification), or performed a simple bind over a clear text (non-SSL/TLS-encrypted) LDAP connection.    Client IP address: <INTERNAL_IP>:36520  Identity the client attempted to authenticate as: AVENTUSGROUP\sergey.sirotin  Binding Type: 1"
                        $userName = ""
                        $clientIp = ""
                        
                        if ($event.Message) {
                            # Extract user name - look for "Identity the client attempted to authenticate as: DOMAIN\username"
                            # Example: "Identity the client attempted to authenticate as: AVENTUSGROUP\sergey.sirotin"
                            if ($event.Message -match "Identity the client attempted to authenticate as:\s*([A-Za-z0-9_\\\.\-]+)") {
                                $userName = $matches[1].Trim()
                            }
                            elseif ($event.Message -match "authenticate as:\s*([A-Za-z0-9_\\\.\-]+)") {
                                $userName = $matches[1].Trim()
                            }
                            elseif ($event.Message -match "([A-Za-z0-9_]+\\[A-Za-z0-9_\.\-]+)") {
                                # Fallback: try to find domain\user pattern
                                $userName = $matches[1]
                            }
                            
                            # Extract IP address - look for "Client IP address: <INTERNAL_IP>:36520" (remove port)
                            # Example: "Client IP address: <INTERNAL_IP>:36520"
                            if ($event.Message -match "Client IP address:\s*([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})(?::[0-9]+)?") {
                                $clientIp = $matches[1]
                            }
                            elseif ($event.Message -match "IP address:\s*([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})(?::[0-9]+)?") {
                                $clientIp = $matches[1]
                            }
                            elseif ($event.Message -match "\b([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})(?::[0-9]+)?\b") {
                                # Fallback: find any IP address pattern
                                $clientIp = $matches[1]
                            }
                        }
                        
                        # If user name not found, try Properties
                        if ([string]::IsNullOrEmpty($userName) -and $event.Properties.Count -gt 0) {
                            foreach ($prop in $event.Properties) {
                                $propValue = $prop.Value
                                if ($propValue) {
                                    $propStr = $propValue.ToString()
                                    # Check if it looks like a domain\user
                                    if ($propStr -match "^[A-Za-z0-9_]+\\[A-Za-z0-9_\.]+$") {
                                        $userName = $propStr
                                        break
                                    }
                                }
                            }
                        }
                        
                        # Clean up message
                        $cleanMessage = $event.Message
                        if ($cleanMessage) {
                            $cleanMessage = $cleanMessage -replace "`r", " "
                            $cleanMessage = $cleanMessage -replace "`n", " "
                            $cleanMessage = $cleanMessage.Trim()
                        }
                        
                        $allParsedEvents = $allParsedEvents + [PSCustomObject]@{
                            LoginDate = [DateTime]$event.TimeCreated
                            UserName = if ([string]::IsNullOrEmpty($userName)) { "Unknown" } else { [string]$userName }
                            ClientIpAddress = if ([string]::IsNullOrEmpty($clientIp)) { $null } else { [string]$clientIp }
                            EventId = [int]$event.Id
                            Message = if ($cleanMessage) { [string]$cleanMessage } else { $null }
                        }
                    }
                }
            }
            catch {
                Write-Warning "    Error querying events with ID $EventID : $_"
            }
        }
        
        if ($allParsedEvents.Count -gt 0) {
            Write-Host "  Found $($allParsedEvents.Count) total parsed events" -ForegroundColor Green
        }
        else {
            Write-Host "  No events found in Directory Service log for the specified period" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Warning "Error getting LDAP events from $ServerName : $_"
    }
    
    return $allParsedEvents
}

# Function to write LDAP login events to database
function Write-LdapLoginEventsToDatabase {
    param(
        [array]$Events,
        [int]$ServerId,
        [string]$ConnString
    )
    
    if ($Events.Count -eq 0) {
        return
    }
    
    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection($ConnString)
        $connection.Open()
        
        $insertQuery = @"
            INSERT INTO fact.LdapUserLogin 
                (LoginDate, ServerId, UserName, ClientIpAddress, EventId, Message)
            VALUES 
                (@LoginDate, @ServerId, @UserName, @ClientIpAddress, @EventId, @Message);
"@
        
        $insertCmd = New-Object System.Data.SqlClient.SqlCommand($insertQuery, $connection)
        $insertCmd.Parameters.Add("@LoginDate", [System.Data.SqlDbType]::DateTime2) | Out-Null
        $insertCmd.Parameters.Add("@ServerId", [System.Data.SqlDbType]::Int) | Out-Null
        $insertCmd.Parameters.Add("@UserName", [System.Data.SqlDbType]::NVarChar, 255) | Out-Null
        $insertCmd.Parameters.Add("@ClientIpAddress", [System.Data.SqlDbType]::NVarChar, 50) | Out-Null
        $insertCmd.Parameters.Add("@EventId", [System.Data.SqlDbType]::Int) | Out-Null
        $insertCmd.Parameters.Add("@Message", [System.Data.SqlDbType]::NVarChar) | Out-Null
        
        $inserted = 0
        
        foreach ($event in $Events) {
            $insertCmd.Parameters["@LoginDate"].Value = $event.LoginDate
            $insertCmd.Parameters["@ServerId"].Value = $ServerId
            $insertCmd.Parameters["@UserName"].Value = $event.UserName
            if ($event.ClientIpAddress) {
                $insertCmd.Parameters["@ClientIpAddress"].Value = $event.ClientIpAddress
            }
            else {
                $insertCmd.Parameters["@ClientIpAddress"].Value = [DBNull]::Value
            }
            $insertCmd.Parameters["@EventId"].Value = $event.EventId
            if ($event.Message) {
                $insertCmd.Parameters["@Message"].Value = $event.Message
            }
            else {
                $insertCmd.Parameters["@Message"].Value = [DBNull]::Value
            }
            
            try {
                $insertCmd.ExecuteNonQuery() | Out-Null
                $inserted++
            }
            catch {
                Write-Warning "Error inserting LDAP login event: $_"
            }
        }
        
        $connection.Close()
        Write-Host "Inserted $inserted LDAP login events for server ID $ServerId" -ForegroundColor Green
    }
    catch {
        Write-Error "Error writing LDAP login events to database: $_"
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
    Write-Host "Getting DCs from database..." -ForegroundColor Cyan
    $servers = Get-DomainControllersFromDatabase -ConnString $ConnectionString
    
    if ($servers.Count -eq 0) {
        Write-Host "No DCs found in database, trying Active Directory..." -ForegroundColor Yellow
        $servers = Get-DomainControllersFromAD
    }
}

if ($servers -eq $null -or $servers.Count -eq 0) {
    Write-Error "No Domain Controllers found. Exiting."
    exit 1
}

Write-Host "Found $($servers.Count) Domain Controllers" -ForegroundColor Green
if ($servers.Count -gt 0) {
    Write-Host "DCs: $($servers.ServerName -join ', ')" -ForegroundColor Gray
}

$startTime = (Get-Date).AddDays(-$DaysBack)
Write-Host "Check period: from $startTime" -ForegroundColor Cyan
Write-Host "Event IDs to check: $($ldapEventIds -join ', ')" -ForegroundColor Cyan
Write-Host "Checking LDAP login events..." -ForegroundColor Cyan

$allEvents = @()

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
    
    # Check if server is reachable (use FQDN if available, otherwise short name)
    $pingTarget = if ($server.FQDN) { $server.FQDN } else { $serverName }
    if (-not (Test-Connection -ComputerName $pingTarget -Count 1 -Quiet)) {
        Write-Warning "Server $pingTarget is unavailable (ping failed) - Skipping"
        continue
    }
    
    # Get LDAP login events
    try {
        $serverFQDN = if ($server.FQDN) { $server.FQDN } else { $null }
        $events = Get-LdapLoginEventsFromServer -ServerName $serverName -ServerFQDN $serverFQDN -EventIds $ldapEventIds -StartTime $startTime
        
        if ($events -and $events.Count -gt 0) {
            Write-Host "  Found $($events.Count) LDAP login events" -ForegroundColor Green
            foreach ($event in $events) {
                $event | Add-Member -MemberType NoteProperty -Name "ServerId" -Value $serverId
                $event | Add-Member -MemberType NoteProperty -Name "ServerName" -Value $serverName
            }
            $allEvents = $allEvents + $events
        }
        else {
            Write-Host "  No LDAP login events found" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Warning "Error getting events from $serverName : $_"
    }
}

Write-Host "`n=== Results ===" -ForegroundColor Cyan
Write-Host "DCs checked: $($servers.Count)" -ForegroundColor Green
Write-Host "Total events found: $($allEvents.Count)" -ForegroundColor Green

if ($allEvents.Count -gt 0) {
    Write-Host "Sample events:" -ForegroundColor Cyan
    $allEvents | Select-Object -First 3 | ForEach-Object {
        Write-Host "  $($_.LoginDate) - $($_.UserName) from $($_.ClientIpAddress)" -ForegroundColor Gray
    }
    
    Write-Host "Writing results to database..." -ForegroundColor Cyan
    
    # Group by server
    $byServer = $allEvents | Group-Object -Property ServerId
    
    foreach ($group in $byServer) {
        Write-LdapLoginEventsToDatabase -Events $group.Group -ServerId $group.Name -ConnString $ConnectionString
    }
}

Write-Host "=== Done ===" -ForegroundColor Green

