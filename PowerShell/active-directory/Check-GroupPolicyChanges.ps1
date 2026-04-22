# Sanitized sample from an internal infrastructure monitoring project.
# Secrets, internal identifiers, and localized text have been removed or generalized.

# Script for checking Group Policy changes in Active Directory
# Writes results to Monitoring database

param(
    [string]$ConnectionString = "Server=<SQL_SERVER>;Database=<MONITORING_DATABASE>;User ID=<SQL_USERNAME>;Password=<SQL_PASSWORD>;TrustServerCertificate=True;",
    [string[]]$DomainControllers = @(),
    [int]$HoursBack = 24,
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
            $servers += [PSCustomObject]@{
                ServerId = $row["ServerId"]
                ServerName = $row["ServerName"]
            }
        }
        
        $connection.Close()
        return $servers
    }
    catch {
        Write-Error "Error getting DC list from database: $_"
        return @()
    }
}

# Function to convert SID to username
function Convert-SIDToUserName {
    param([string]$SID)
    try {
        $user = (New-Object System.Security.Principal.SecurityIdentifier($SID)).Translate([System.Security.Principal.NTAccount]).Value
        $username = $user.Split('\')[-1]  # Only username, without domain
        return $username
    }
    catch {
        return $SID
    }
}

# Function to get or create user in database
function Get-OrCreateUser {
    param(
        [string]$Username,
        [string]$ConnString
    )
    
    if ([string]::IsNullOrWhiteSpace($Username)) {
        return $null
    }
    
    try {
        $query = @"
            SELECT UserId FROM dim.User WHERE UPN = @UPN OR DisplayName = @DisplayName
"@
        
        $connection = New-Object System.Data.SqlClient.SqlConnection($ConnString)
        $command = New-Object System.Data.SqlClient.SqlCommand($query, $connection)
        $command.Parameters.AddWithValue("@UPN", $Username) | Out-Null
        $command.Parameters.AddWithValue("@DisplayName", $Username) | Out-Null
        $connection.Open()
        
        $result = $command.ExecuteScalar()
        $connection.Close()
        
        if ($result) {
            return [int]$result
        }
        
        # Create new user
        $insertQuery = @"
            INSERT INTO dim.User (UPN, DisplayName, CreatedAt)
            VALUES (@UPN, @DisplayName, GETDATE());
            SELECT CAST(SCOPE_IDENTITY() AS INT);
"@
        
        $insertCommand = New-Object System.Data.SqlClient.SqlCommand($insertQuery, $connection)
        $insertCommand.Parameters.AddWithValue("@UPN", $Username) | Out-Null
        $insertCommand.Parameters.AddWithValue("@DisplayName", $Username) | Out-Null
        $connection.Open()
        $newUserId = [int]$insertCommand.ExecuteScalar()
        $connection.Close()
        
        return $newUserId
    }
    catch {
        Write-Warning "Error getting/creating user $Username : $_"
        return $null
    }
}

# Function to get or create server in database
function Get-OrCreateServer {
    param(
        [string]$ServerName,
        [string]$ConnString
    )
    
    try {
        $query = @"
            SELECT ServerId FROM dim.Server WHERE ServerName = @ServerName
"@
        
        $connection = New-Object System.Data.SqlClient.SqlConnection($ConnString)
        $command = New-Object System.Data.SqlClient.SqlCommand($query, $connection)
        $command.Parameters.AddWithValue("@ServerName", $ServerName) | Out-Null
        $connection.Open()
        
        $result = $command.ExecuteScalar()
        $connection.Close()
        
        if ($result) {
            return [int]$result
        }
        
        # Create new server
        $insertQuery = @"
            INSERT INTO dim.Server (ServerName, Role, IsActive, CreatedAt)
            VALUES (@ServerName, 'Domain Controller', 1, GETDATE());
            SELECT CAST(SCOPE_IDENTITY() AS INT);
"@
        
        $insertCommand = New-Object System.Data.SqlClient.SqlCommand($insertQuery, $connection)
        $insertCommand.Parameters.AddWithValue("@ServerName", $ServerName) | Out-Null
        $connection.Open()
        $newServerId = [int]$insertCommand.ExecuteScalar()
        $connection.Close()
        
        return $newServerId
    }
    catch {
        Write-Warning "Error getting/creating server $ServerName : $_"
        return 0
    }
}

# Function to extract GPO name from event message or properties
function Get-GpoNameFromEvent {
    param(
        [System.Diagnostics.Eventing.Reader.EventLogRecord]$Event
    )
    
    # Try to get from event message
    $message = $Event.Message
    if ($message) {
        # Look for CN= pattern (common in AD object names)
        if ($message -match "CN=([^,]+)") {
            $gpoName = $matches[1]
            # Remove escaped characters
            $gpoName = $gpoName -replace '\\', ''
            return $gpoName
        }
        
        # Look for "Group Policy" or "GPO" in message
        if ($message -match "(?:Group Policy|GPO)[\s:]+([^\r\n]+)") {
            return $matches[1].Trim()
        }
    }
    
    # Try to get from event properties
    if ($Event.Properties.Count -gt 0) {
        # Property[0] is usually the object name
        $objName = $Event.Properties[0].Value
        if ($objName) {
            # Extract CN from DN
            if ($objName -match "CN=([^,]+)") {
                $gpoName = $matches[1]
                $gpoName = $gpoName -replace '\\', ''
                return $gpoName
            }
            return $objName
        }
    }
    
    return "Unknown GPO"
}

# Function to extract GPO GUID from event
function Get-GpoGuidFromEvent {
    param(
        [System.Diagnostics.Eventing.Reader.EventLogRecord]$Event
    )
    
    $message = $Event.Message
    if ($message) {
        # Look for GUID pattern
        if ($message -match "(\{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\})") {
            return $matches[1]
        }
    }
    
    # Try properties
    if ($Event.Properties.Count -gt 0) {
        foreach ($prop in $Event.Properties) {
            $value = $prop.Value
            if ($value -match "(\{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\})") {
                return $matches[1]
            }
        }
    }
    
    return $null
}

# Function to get Group Policy events from server
function Get-GroupPolicyEventsFromServer {
    param(
        [string]$ServerName,
        [int]$ServerId,
        [DateTime]$StartTime
    )
    
    $events = @()
    
    try {
        $ping = Test-Connection -ComputerName $ServerName -Count 1 -Quiet -ErrorAction SilentlyContinue
        if (-not $ping) {
            Write-Warning "Server $ServerName is unavailable (ping failed)"
            return $events
        }
        
        # Get Group Policy events via Invoke-Command
        $gpEvents = Invoke-Command -ComputerName $ServerName -ScriptBlock {
            param($StartTime)
            
            $events = @()
            try {
                # Event IDs for Group Policy changes:
                # 5136: A directory service object was modified (GPO modified)
                # 5137: A directory service object was created (GPO created)
                # 5139: A directory service object was moved (GPO moved)
                # 5141: A directory service object was deleted (GPO deleted)
                
                Write-Host "    Querying Directory Service log for Group Policy events since $StartTime..." -ForegroundColor Gray
                
                # Check Directory Service log (where GPO events are usually logged)
                $winEvents = $null
                try {
                    $winEvents = Get-WinEvent -FilterHashtable @{
                        LogName = 'Directory Service'
                        Id = @(5136, 5137, 5139, 5141)
                        StartTime = $StartTime
                    } -ErrorAction Stop
                    Write-Host "    Found $($winEvents.Count) event(s) in Directory Service log" -ForegroundColor Green
                }
                catch {
                    if ($_.Exception.Message -like "*No events*" -or $_.Exception.Message -like "*No events were found*") {
                        Write-Host "    No Group Policy events found in Directory Service log" -ForegroundColor Gray
                    }
                    else {
                        Write-Host "    Error querying Directory Service log: $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                    $winEvents = @()
                }
                
                # Also check Security log for GPO-related events
                try {
                    $securityEvents = Get-WinEvent -FilterHashtable @{
                        LogName = 'Security'
                        Id = @(5136, 5137, 5139, 5141)
                        StartTime = $StartTime
                    } -ErrorAction SilentlyContinue
                    
                    if ($securityEvents) {
                        Write-Host "    Found $($securityEvents.Count) additional event(s) in Security log" -ForegroundColor Green
                        $winEvents = $winEvents + $securityEvents
                    }
                }
                catch {
                    # Ignore
                }
                
                # Filter events to only include Group Policy objects
                foreach ($event in $winEvents) {
                    $message = $event.Message
                    $objectClass = $null
                    
                    # Check if this is a GPO event by looking at the object class or DN
                    if ($message) {
                        # GPO objects are usually in CN=Policies,CN=System container
                        if ($message -match "CN=Policies" -or $message -match "Group Policy" -or $message -match "GPO") {
                            # Extract object class
                            if ($message -match "Object Class:\s*([^\r\n]+)") {
                                $objectClass = $matches[1].Trim()
                            }
                            
                            # Check if it's a groupPolicyContainer (GPO object class)
                            if ($message -match "groupPolicyContainer" -or $objectClass -eq "groupPolicyContainer") {
                                $events += $event
                            }
                        }
                    }
                    
                    # Also check event properties
                    if ($event.Properties.Count -gt 0) {
                        $objDN = $event.Properties[0].Value
                        if ($objDN -and ($objDN -match "CN=Policies" -or $objDN -match "groupPolicyContainer")) {
                            if (-not ($events -contains $event)) {
                                $events += $event
                            }
                        }
                    }
                }
                
                Write-Host "    Filtered to $($events.Count) Group Policy event(s)" -ForegroundColor Cyan
            }
            catch {
                Write-Warning "Error getting events: $_"
            }
            
            return $events
        } -ArgumentList $StartTime -ErrorAction SilentlyContinue
        
        if ($gpEvents) {
            foreach ($event in $gpEvents) {
                $action = switch ($event.Id) {
                    5137 { "Created" }
                    5136 { "Modified" }
                    5139 { "Moved" }
                    5141 { "Deleted" }
                    default { "Unknown" }
                }
                
                $gpoName = Get-GpoNameFromEvent -Event $event
                $gpoGuid = Get-GpoGuidFromEvent -Event $event
                
                # Extract performed by user
                $performedBy = $null
                if ($event.Properties.Count -gt 2) {
                    # Usually Properties[2] or Properties[3] contains the subject/user
                    try {
                        $subjectSid = $event.Properties[2].Value
                        if ($subjectSid) {
                            $performedBy = Convert-SIDToUserName -SID $subjectSid
                        }
                    }
                    catch {
                        # Try other properties
                        if ($event.Properties.Count -gt 3) {
                            try {
                                $subjectName = $event.Properties[3].Value
                                if ($subjectName) {
                                    $performedBy = $subjectName.Split('\')[-1]
                                }
                            }
                            catch {
                                # Ignore
                            }
                        }
                    }
                }
                
                # Extract from message if not found in properties
                if (-not $performedBy) {
                    $message = $event.Message
                    if ($message -match "Subject:\s*([^\r\n]+)") {
                        $subject = $matches[1].Trim()
                        $performedBy = $subject.Split('\')[-1]
                    }
                }
                
                $events += [PSCustomObject]@{
                    EventTime = $event.TimeCreated
                    GpoName = $gpoName
                    GpoGuid = $gpoGuid
                    Action = $action
                    EventId = $event.Id
                    PerformedBy = $performedBy
                    ServerId = $ServerId
                    ServerName = $ServerName
                }
            }
        }
    }
    catch {
        Write-Warning "Error getting Group Policy events from $ServerName : $_"
    }
    
    return $events
}

# Main script
Write-Host "=== Checking Group Policy changes for the last $HoursBack hours ===" -ForegroundColor Cyan

# Get list of Domain Controllers
if ($UseDefaultControllers -or $DomainControllers.Count -eq 0) {
    Write-Host "Getting list of Domain Controllers..." -ForegroundColor Yellow
    $servers = $defaultDomainControllers | ForEach-Object {
        [PSCustomObject]@{
            ServerId = 0
            ServerName = $_
        }
    }
    Write-Host "Using default DCs: $($servers.ServerName -join ', ')" -ForegroundColor Green
}
else {
    Write-Host "Getting DCs from database..." -ForegroundColor Yellow
    $servers = Get-DomainControllersFromDatabase -ConnString $ConnectionString
    if ($servers.Count -eq 0) {
        Write-Host "No DCs found in database, using provided list" -ForegroundColor Yellow
        $servers = $DomainControllers | ForEach-Object {
            [PSCustomObject]@{
                ServerId = 0
                ServerName = $_
            }
        }
    }
    else {
        Write-Host "Found DCs: $($servers.ServerName -join ', ')" -ForegroundColor Green
    }
}

if ($servers.Count -eq 0) {
    Write-Error "No Domain Controllers specified"
    exit 1
}

$startTime = (Get-Date).AddHours(-$HoursBack)
Write-Host "Check period: from $startTime" -ForegroundColor Yellow

# Collect events from all DCs
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
    
    # Check if server is reachable
    if (-not (Test-Connection -ComputerName $serverName -Count 1 -Quiet)) {
        Write-Warning "Server $serverName is unavailable (ping failed) - Skipping"
        continue
    }
    
    # Get Group Policy events
    $events = Get-GroupPolicyEventsFromServer -ServerName $serverName -ServerId $serverId -StartTime $startTime
    
    if ($events.Count -gt 0) {
        Write-Host "  ✓ Found events: $($events.Count)" -ForegroundColor Green
        $allEvents = $allEvents + $events
    }
    else {
        Write-Host "  - No events found" -ForegroundColor Gray
    }
}

Write-Host "`n=== Results ===" -ForegroundColor Cyan
Write-Host "DCs checked: $($servers.Count)" -ForegroundColor Green
Write-Host "Total events: $($allEvents.Count)" -ForegroundColor Green

if ($allEvents.Count -gt 0) {
    # Connect to database
    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
        $connection.Open()
        Write-Host "Writing results to database..." -ForegroundColor Yellow
        
        $insertQuery = @"
            INSERT INTO fact.GroupPolicyEvent (
                EventTime,
                DomainControllerId,
                GpoName,
                GpoGuid,
                Action,
                EventId,
                PerformedByUserId,
                PerformedByRaw,
                Source
            )
            VALUES (
                @EventTime,
                @DomainControllerId,
                @GpoName,
                @GpoGuid,
                @Action,
                @EventId,
                @PerformedByUserId,
                @PerformedByRaw,
                @Source
            )
"@
        
        $insertCmd = New-Object System.Data.SqlClient.SqlCommand($insertQuery, $connection)
        $insertedCount = 0
        
        foreach ($event in $allEvents) {
            # Get or create user
            $userId = $null
            if ($event.PerformedBy) {
                $userId = Get-OrCreateUser -Username $event.PerformedBy -ConnString $ConnectionString
            }
            
            $insertCmd.Parameters.Clear()
            $insertCmd.Parameters.AddWithValue("@EventTime", $event.EventTime) | Out-Null
            $insertCmd.Parameters.AddWithValue("@DomainControllerId", $event.ServerId) | Out-Null
            $insertCmd.Parameters.AddWithValue("@GpoName", $event.GpoName) | Out-Null
            
            if ($event.GpoGuid) {
                $insertCmd.Parameters.AddWithValue("@GpoGuid", $event.GpoGuid) | Out-Null
            }
            else {
                $insertCmd.Parameters.AddWithValue("@GpoGuid", [DBNull]::Value) | Out-Null
            }
            
            $insertCmd.Parameters.AddWithValue("@Action", $event.Action) | Out-Null
            $insertCmd.Parameters.AddWithValue("@EventId", $event.EventId) | Out-Null
            
            if ($userId) {
                $insertCmd.Parameters.AddWithValue("@PerformedByUserId", $userId) | Out-Null
            }
            else {
                $insertCmd.Parameters.AddWithValue("@PerformedByUserId", [DBNull]::Value) | Out-Null
            }
            
            if ($event.PerformedBy) {
                $insertCmd.Parameters.AddWithValue("@PerformedByRaw", $event.PerformedBy) | Out-Null
            }
            else {
                $insertCmd.Parameters.AddWithValue("@PerformedByRaw", [DBNull]::Value) | Out-Null
            }
            
            $insertCmd.Parameters.AddWithValue("@Source", "Check-GroupPolicyChanges") | Out-Null
            
            try {
                $insertCmd.ExecuteNonQuery() | Out-Null
                $insertedCount++
            }
            catch {
                Write-Warning "Error inserting event: $_"
            }
        }
        
        $connection.Close()
        Write-Host "Successfully written: $insertedCount Group Policy events" -ForegroundColor Green
    }
    catch {
        Write-Error "Error writing to database: $_"
    }
}
else {
    Write-Host "No Group Policy events to write" -ForegroundColor Yellow
}

Write-Host "`n=== Done ===" -ForegroundColor Green

