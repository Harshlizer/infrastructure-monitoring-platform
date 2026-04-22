# Sanitized sample from an internal infrastructure monitoring project.
# Secrets, internal identifiers, and localized text have been removed or generalized.

# Script for checking changes in Active Directory users and groups
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

# Function to convert SID to username (like in DNS script)
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

# Function to get DisplayName from Active Directory
function Get-UserDisplayNameFromAD {
    param(
        [string]$UPN,
        [string]$Username
    )
    
    try {
        Import-Module ActiveDirectory -ErrorAction SilentlyContinue
        
        # Try to find user by UPN
        if ($UPN -and $UPN -like "*@*") {
            $adUser = Get-ADUser -Filter "UserPrincipalName -eq '$UPN'" -Properties DisplayName -ErrorAction SilentlyContinue
            if ($adUser -and $adUser.DisplayName) {
                return $adUser.DisplayName
            }
        }
        
        # Try to find user by SamAccountName (username part before @)
        if ($UPN -and $UPN -like "*@*") {
            $samAccountName = ($UPN -split "@")[0]
            $adUser = Get-ADUser -Filter "SamAccountName -eq '$samAccountName'" -Properties DisplayName -ErrorAction SilentlyContinue
            if ($adUser -and $adUser.DisplayName) {
                return $adUser.DisplayName
            }
        }
        
        # Try using Username parameter
        if ($Username) {
            $adUser = Get-ADUser -Filter "SamAccountName -eq '$Username'" -Properties DisplayName -ErrorAction SilentlyContinue
            if ($adUser -and $adUser.DisplayName) {
                return $adUser.DisplayName
            }
        }
        
        return $null
    }
    catch {
        # If AD module is not available or user not found, return null
        return $null
    }
}

# Function to get or create user in database
function Get-OrCreateUser {
    param(
        [string]$UPN,
        [string]$DisplayName,
        [System.Data.SqlClient.SqlConnection]$Connection
    )
    
    try {
        # Search for user
        $findQuery = "SELECT UserId, DisplayName FROM dim.[User] WHERE UPN = @UPN"
        $findCmd = New-Object System.Data.SqlClient.SqlCommand($findQuery, $Connection)
        $findCmd.Parameters.AddWithValue("@UPN", $UPN) | Out-Null
        $reader = $findCmd.ExecuteReader()
        
        if ($reader.Read()) {
            $userId = [int]$reader["UserId"]
            $existingDisplayName = if (-not $reader.IsDBNull($reader.GetOrdinal("DisplayName"))) { [string]$reader["DisplayName"] } else { $null }
            $reader.Close()
            
            # If user exists but DisplayName is missing, try to get it from AD and update
            if (-not $existingDisplayName -or $existingDisplayName -like "S-*" -or $existingDisplayName -like "*@s-*") {
                $usernameFromUPN = if ($UPN -like "*@*") { ($UPN -split "@")[0] } else { $UPN }
                $adDisplayName = Get-UserDisplayNameFromAD -UPN $UPN -Username $usernameFromUPN
                
                if ($adDisplayName) {
                    # Update DisplayName
                    $updateQuery = "UPDATE dim.[User] SET DisplayName = @DisplayName WHERE UserId = @UserId"
                    $updateCmd = New-Object System.Data.SqlClient.SqlCommand($updateQuery, $Connection)
                    $updateCmd.Parameters.AddWithValue("@DisplayName", $adDisplayName) | Out-Null
                    $updateCmd.Parameters.AddWithValue("@UserId", $userId) | Out-Null
                    $updateCmd.ExecuteNonQuery() | Out-Null
                    Write-Host "Updated DisplayName for user $UPN : $adDisplayName" -ForegroundColor Green
                }
            }
            
            return $userId
        }
        $reader.Close()
        
        # If DisplayName is not provided or contains SID, try to get it from AD
        if (-not $DisplayName -or $DisplayName -like "S-*" -or $DisplayName -like "*@s-*") {
            $usernameFromUPN = if ($UPN -like "*@*") { ($UPN -split "@")[0] } else { $UPN }
            $adDisplayName = Get-UserDisplayNameFromAD -UPN $UPN -Username $usernameFromUPN
            
            if ($adDisplayName) {
                $DisplayName = $adDisplayName
            }
            elseif (-not $DisplayName) {
                # Use username as fallback
                $DisplayName = $usernameFromUPN
            }
        }
        
        # Create new user
        $insertQuery = @"
            INSERT INTO dim.[User] (UPN, DisplayName, Source, IsActive, CreatedAt)
            OUTPUT INSERTED.UserId
            VALUES (@UPN, @DisplayName, 'AD', 1, GETUTCDATE())
"@
        $insertCmd = New-Object System.Data.SqlClient.SqlCommand($insertQuery, $Connection)
        $insertCmd.Parameters.AddWithValue("@UPN", $UPN) | Out-Null
        $displayNameValue = if ($DisplayName) { [object]$DisplayName } else { [DBNull]::Value }
        $insertCmd.Parameters.AddWithValue("@DisplayName", $displayNameValue) | Out-Null
        $userId = [int]$insertCmd.ExecuteScalar()
        
        return $userId
    }
    catch {
        Write-Warning "Error searching/creating user $UPN : $_"
        return $null
    }
}

# Function to get AD events from server
function Get-AdEventsFromServer {
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
        
        # Get AD events via Invoke-Command
        $adEvents = Invoke-Command -ComputerName $ServerName -ScriptBlock {
            param($StartTime)
            
            $events = @()
            try {
                # User creation/deletion events: 4720 (created), 4726 (deleted)
                # Group creation/deletion events: 4727 (created), 4729 (deleted)
                # Group membership change events: 4728 (added), 4732 (removed), 4756 (added), 4757 (removed)
                
                Write-Host "    Querying Security log for events since $StartTime..." -ForegroundColor Gray
                
                # Diagnostic: Check if Security log is accessible and has any events
                try {
                    $testEvents = Get-WinEvent -FilterHashtable @{
                        LogName = 'Security'
                        StartTime = $StartTime
                    } -MaxEvents 5 -ErrorAction SilentlyContinue
                    if ($testEvents) {
                        Write-Host "    Security log is accessible. Found $($testEvents.Count) recent event(s)." -ForegroundColor Gray
                        # Show what Event IDs are available
                        $availableIds = $testEvents | Select-Object -ExpandProperty Id -Unique
                        Write-Host "    Available Event IDs in recent events: $($availableIds -join ', ')" -ForegroundColor Gray
                    }
                }
                catch {
                    Write-Host "    Warning: Could not access Security log for diagnostics" -ForegroundColor Yellow
                }
                
                # Try Security log first
                $winEvents = $null
                try {
                    $winEvents = Get-WinEvent -FilterHashtable @{
                        LogName = 'Security'
                        Id = @(4720, 4726, 4727, 4729, 4728, 4732, 4756, 4757)
                        StartTime = $StartTime
                    } -ErrorAction Stop
                    Write-Host "    Found $($winEvents.Count) event(s) in Security log with matching IDs" -ForegroundColor Green
                }
                catch {
                    # If no events found, Get-WinEvent throws an exception
                    if ($_.Exception.Message -like "*No events*" -or $_.Exception.Message -like "*No events were found*") {
                        Write-Host "    No events found in Security log for the specified period" -ForegroundColor Gray
                        Write-Host "    Checking if any AD-related events exist with different IDs..." -ForegroundColor Gray
                        # Try to find any AD-related events
                        try {
                            $adRelatedIds = @(4720, 4726, 4727, 4729, 4728, 4732, 4756, 4757, 5136, 5137, 5139, 5141, 4662, 4661)
                            $foundIds = @()
                            foreach ($eventId in $adRelatedIds) {
                                $testEvent = Get-WinEvent -FilterHashtable @{
                                    LogName = 'Security'
                                    Id = $eventId
                                    StartTime = $StartTime
                                } -MaxEvents 1 -ErrorAction SilentlyContinue
                                if ($testEvent) {
                                    $foundIds += $eventId
                                }
                            }
                            if ($foundIds.Count -gt 0) {
                                Write-Host "    Found events with IDs: $($foundIds -join ', ')" -ForegroundColor Yellow
                            } else {
                                Write-Host "    No AD-related events found with any of the checked IDs" -ForegroundColor Yellow
                            }
                        }
                        catch {
                            # Ignore
                        }
                    }
                    else {
                        Write-Host "    Error querying Security log: $($_.Exception.Message)" -ForegroundColor Yellow
                    }
                    $winEvents = @()
                }
                
                # Also check Directory Service log for some AD events
                # Some group operations might be logged there
                $dsEvents = $null
                try {
                    $dsEvents = Get-WinEvent -FilterHashtable @{
                        LogName = 'Directory Service'
                        Id = @(5136, 5137, 5139, 5141)  # AD object modifications
                        StartTime = $StartTime
                    } -ErrorAction SilentlyContinue
                    if ($dsEvents) {
                        Write-Host "    Found $($dsEvents.Count) event(s) in Directory Service log" -ForegroundColor Gray
                    }
                }
                catch {
                    # Directory Service log might not exist or have no events
                    $dsEvents = @()
                }
                
                # Combine events from both logs
                $allEvents = @()
                if ($winEvents) {
                    $allEvents += $winEvents
                }
                if ($dsEvents) {
                    $allEvents += $dsEvents
                }
                
                $winEvents = $allEvents
                
                foreach ($event in $winEvents) {
                    $action = switch ($event.Id) {
                        4720 { "Created" }  # User created
                        4726 { "Deleted" }  # User deleted
                        4727 { "Created" }  # Group created
                        4729 { "Deleted" }  # Group deleted
                        4728 { "Add" }      # Added to group (global)
                        4732 { "Remove" }  # Removed from group (global)
                        4756 { "Add" }      # Added to group (universal)
                        4757 { "Remove" }   # Removed from group (universal)
                        default { "Unknown" }
                    }
                    
                    $targetType = if ($event.Id -eq 4720 -or $event.Id -eq 4726) {
                        "User"
                    }
                    elseif ($event.Id -eq 4727 -or $event.Id -eq 4729) {
                        "Group"
                    }
                    else {
                        "GroupMember"
                    }
                    
                    $targetName = $null
                    $memberName = $null
                    $memberType = $null
                    $performedBy = $null
                    
                    # Extract data from event properties
                    # Event properties structure for AD events:
                    # Event 4728 (Add to group): Properties[0]=TargetUserName, Properties[1]=TargetDomainName, Properties[2]=TargetSid, 
                    #                            Properties[3]=SubjectUserName, Properties[4]=SubjectDomainName, Properties[5]=SubjectUserSid,
                    #                            Properties[6]=GroupName, Properties[7]=GroupSid, Properties[8]=MemberSid, Properties[9]=MemberName
                    # Event 4720 (User created): Properties[0]=TargetUserName, Properties[1]=TargetDomainName, Properties[2]=TargetSid,
                    #                            Properties[3]=SubjectUserName, Properties[4]=SubjectDomainName, Properties[5]=SubjectUserSid
                    
                    if ($event.Properties.Count -gt 0) {
                        # Extract PerformedBy (Subject) - who performed the action
                        # Usually in Properties[3] (SubjectUserName) and Properties[4] (SubjectDomainName)
                        # Properties[5] contains SubjectUserSid
                        if ($event.Properties.Count -gt 4) {
                            $subjectUserName = if ($event.Properties[3].Value) { [string]$event.Properties[3].Value } else { $null }
                            $subjectDomainName = if ($event.Properties[4].Value) { [string]$event.Properties[4].Value } else { $null }
                            $subjectUserSid = if ($event.Properties.Count -gt 5 -and $event.Properties[5].Value) { [string]$event.Properties[5].Value } else { $null }
                            
                            # Extract username (like in DNS script) - just the username, not UPN
                            if ($subjectUserName) {
                                # If username is in format DOMAIN\Username, extract just username
                                if ($subjectUserName -match "^[A-Za-z0-9_\-\.]+\\([A-Za-z0-9_\-\.]+)$") {
                                    $performedBy = $matches[1]  # Just username
                                }
                                # If it's already a UPN, extract username part
                                elseif ($subjectUserName -like "*@*") {
                                    $performedBy = ($subjectUserName -split "@")[0]  # Just username
                                }
                                # Otherwise use as is
                                else {
                                    $performedBy = $subjectUserName
                                }
                            }
                            # If we have SID, convert it to username (like in DNS script)
                            elseif ($subjectUserSid -and $subjectUserSid -like "S-*") {
                                $performedBy = Convert-SIDToUserName -SID $subjectUserSid
                            }
                        }
                        # Fallback: try Properties[2] or Properties[1] for subject
                        elseif ($event.Properties.Count -gt 2) {
                            $subjectValue = if ($event.Properties[2].Value) { [string]$event.Properties[2].Value } else { $null }
                            if ($subjectValue -and $subjectValue -notlike "S-*") {
                                $performedBy = $subjectValue
                            }
                        }
                        
                        # For user/group events: Properties[0] usually contains target name
                        if ($targetType -eq "User" -or $targetType -eq "Group") {
                            $targetName = if ($event.Properties[0].Value) { [string]$event.Properties[0].Value } else { $null }
                        }
                        # For membership events: Properties[0] - group, Properties[1] - member (like in old working script)
                        elseif ($targetType -eq "GroupMember") {
                            # Group name is in Properties[0] for membership events (as in old working script)
                            if ($event.Properties.Count -gt 0 -and $event.Properties[0].Value) {
                                $targetName = [string]$event.Properties[0].Value
                            }
                            
                            # Member name is in Properties[1] for membership events (as in old working script)
                            if ($event.Properties.Count -gt 1 -and $event.Properties[1].Value) {
                                $memberName = [string]$event.Properties[1].Value
                            }
                            
                            # Fallback: try Properties[6] for group and Properties[9] for member (for some event IDs like 4728)
                            if (-not $targetName -and $event.Properties.Count -gt 6 -and $event.Properties[6].Value) {
                                $targetName = [string]$event.Properties[6].Value
                            }
                            if (-not $memberName -and $event.Properties.Count -gt 9 -and $event.Properties[9].Value) {
                                $memberName = [string]$event.Properties[9].Value
                            }
                        }
                    }
                    
                    $events += @{
                        EventTime = $event.TimeCreated
                        Action = $action
                        TargetType = $targetType
                        TargetName = $targetName
                        MemberName = $memberName
                        MemberType = $memberType
                        PerformedBy = $performedBy
                        Message = $event.Message
                    }
                }
            }
            catch {
                Write-Warning "Error getting AD events: $_"
            }
            
            return $events
        } -ArgumentList $StartTime -ErrorAction Stop
        
        foreach ($adEvent in $adEvents) {
            $performedBy = $null
            if ($adEvent.PerformedBy) {
                $performedByValue = $adEvent.PerformedBy
                
                # If it's in format "SID\DOMAIN" (e.g., "S-1-5-21-...\AVENTUSGROUP"), convert SID to username
                if ($performedByValue -match "^S-\d+-\d+[^\\]*\\([A-Za-z0-9_\-\.]+)$") {
                    $sidPart = $performedByValue -replace "\\[^\\]+$", ""
                    $domainPart = $matches[1]
                    try {
                        $sid = New-Object System.Security.Principal.SecurityIdentifier($sidPart)
                        $account = $sid.Translate([System.Security.Principal.NTAccount])
                        $accountValue = $account.Value
                        # Extract username from DOMAIN\Username format
                        if ($accountValue -match "^[A-Za-z0-9_\-\.]+\\([A-Za-z0-9_\-\.]+)$") {
                            $username = $matches[1]
                            # Create UPN: username@domain.local
                            $domainLower = $domainPart.ToLower()
                            $performedBy = "$username@$domainLower.local"
                        }
                        else {
                            # If account value doesn't match pattern, try to extract username
                            if ($accountValue -like "*\*") {
                                $username = ($accountValue -split "\\")[-1]
                                $domainLower = $domainPart.ToLower()
                                $performedBy = "$username@$domainLower.local"
                            }
                            else {
                                $performedBy = $accountValue
                            }
                        }
                    }
                    catch {
                        Write-Warning "Could not convert SID to username: $sidPart"
                        # Fallback: use domain name as username (not ideal, but better than SID)
                        $domainLower = $domainPart.ToLower()
                        $performedBy = "$domainPart@$domainLower.local"
                    }
                }
                # If it's in format "DOMAIN\Username", extract just username (like in DNS script)
                elseif ($performedByValue -match "^[A-Za-z0-9_\-\.]+\\([A-Za-z0-9_\-\.]+)$") {
                    $username = $matches[1]
                    # Just use username, not UPN (like in DNS script)
                    $performedBy = $username
                }
                # If it's a pure SID (starts with S-), try to convert
                elseif ($performedByValue -like "S-*" -and $performedByValue -notlike "*\\*") {
                    try {
                        $sid = New-Object System.Security.Principal.SecurityIdentifier($performedByValue)
                        $account = $sid.Translate([System.Security.Principal.NTAccount])
                        $accountValue = $account.Value
                        # Extract username from DOMAIN\Username format
                        if ($accountValue -match "^[A-Za-z0-9_\-\.]+\\([A-Za-z0-9_\-\.]+)$") {
                            $username = $matches[1]
                            $domain = ($accountValue -split "\\")[0]
                            $domainLower = $domain.ToLower()
                            $performedBy = "$username@$domainLower.local"
                        }
                        else {
                            $performedBy = $accountValue
                        }
                    }
                    catch {
                        Write-Warning "Could not convert SID to username: $performedByValue"
                    }
                }
                # If it contains @, it's already a UPN (but check it's not SID@something)
                elseif ($performedByValue -like "*@*" -and $performedByValue -notlike "S-*") {
                    $performedBy = $performedByValue
                }
                # Otherwise use as is (but warn if it looks like SID)
                else {
                    if ($performedByValue -like "S-*") {
                        Write-Warning "Unexpected SID format: $performedByValue"
                    }
                    $performedBy = $performedByValue
                }
            }
            
            $events += [PSCustomObject]@{
                ServerId = $ServerId
                ServerName = $ServerName
                EventTime = $adEvent.EventTime
                Action = $adEvent.Action
                TargetType = $adEvent.TargetType
                TargetName = $adEvent.TargetName
                MemberName = $adEvent.MemberName
                MemberType = $adEvent.MemberType
                PerformedBy = $performedBy
            }
        }
    }
    catch {
        Write-Warning "Error checking AD events on $ServerName : $_"
    }
    
    return $events
}

# Function to write results to database
function Write-AdEventsToDatabase {
    param(
        [array]$Events,
        [string]$ConnString
    )
    
    if ($Events.Count -eq 0) {
        Write-Warning "No data to write"
        return
    }
    
    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection($ConnString)
        $connection.Open()
        
        $groupEventsCount = 0
        
        foreach ($event in $Events) {
            # Extract values from event object and convert to proper types
            $eventServerId = [int]$event.ServerId
            $eventServerName = [string]$event.ServerName
            $eventEventTime = [DateTime]$event.EventTime
            $eventTargetType = [string]$event.TargetType
            $eventTargetName = if ($event.TargetName) { [string]$event.TargetName } else { $null }
            $eventMemberName = if ($event.MemberName) { [string]$event.MemberName } else { $null }
            $eventMemberType = if ($event.MemberType) { [string]$event.MemberType } else { $null }
            $eventAction = [string]$event.Action
            $eventPerformedBy = if ($event.PerformedBy) { [string]$event.PerformedBy } else { $null }
            
            # If ServerId = 0, try to find or create server in database
            $serverId = $eventServerId
            if ($serverId -eq 0) {
                try {
                    $findQuery = "SELECT ServerId FROM dim.Server WHERE ServerName = @ServerName"
                    $findCmd = New-Object System.Data.SqlClient.SqlCommand($findQuery, $connection)
                    $findCmd.Parameters.AddWithValue("@ServerName", $eventServerName) | Out-Null
                    $serverIdObj = $findCmd.ExecuteScalar()
                    
                    if ($serverIdObj) {
                        $serverId = [int]$serverIdObj
                    }
                    else {
                        # Create new server
                        $insertServerQuery = @"
                            INSERT INTO dim.Server (ServerName, Role, IsActive, CreatedAt)
                            OUTPUT INSERTED.ServerId
                            VALUES (@ServerName, 'DC', 1, GETUTCDATE())
"@
                        $insertCmd = New-Object System.Data.SqlClient.SqlCommand($insertServerQuery, $connection)
                        $insertCmd.Parameters.AddWithValue("@ServerName", $eventServerName) | Out-Null
                        $serverId = [int]$insertCmd.ExecuteScalar()
                        Write-Host "Created new server in DB: $eventServerName (ID: $serverId)" -ForegroundColor Green
                    }
                }
                catch {
                    Write-Warning "Error searching/creating server $eventServerName in DB: $_"
                    continue
                }
            }
            
            # Write all events to fact.AdGroupEvent
            # For user/group creation/deletion, we use special values:
            # - User created/deleted: TargetGroup = "SYSTEM", MemberName = username, MemberType = "User"
            # - Group created/deleted: TargetGroup = groupname, MemberName = "SYSTEM", MemberType = "Group"
            # - Group membership: TargetGroup = groupname, MemberName = member, MemberType = member type
            
            $performedByUserId = $null
            $performedByRawClean = $null
            
            if ($eventPerformedBy) {
                # eventPerformedBy should already be just username (like in DNS script)
                # But clean it up to ensure it's just username, not SID or UPN
                $performedByRawClean = $eventPerformedBy
                
                # If it's a SID, convert to username (like in DNS script)
                if ($performedByRawClean -like "S-*") {
                    $performedByRawClean = Convert-SIDToUserName -SID $performedByRawClean
                }
                # If it's in format DOMAIN\Username, extract just username
                elseif ($performedByRawClean -match "^[A-Za-z0-9_\-\.]+\\([A-Za-z0-9_\-\.]+)$") {
                    $performedByRawClean = $matches[1]
                }
                # If it's UPN (contains @), extract username part
                elseif ($performedByRawClean -like "*@*") {
                    $performedByRawClean = ($performedByRawClean -split "@")[0]
                }
                
                # Create UPN for database lookup (username@domain.local)
                $upn = if ($performedByRawClean -notlike "*@*") {
                    "$performedByRawClean@$($env:USERDNSDOMAIN)"
                }
                else {
                    $performedByRawClean
                }
                
                # Get-OrCreateUser will automatically fetch DisplayName from AD
                $performedByUserId = Get-OrCreateUser -UPN $upn -DisplayName $performedByRawClean -Connection $connection
            }
            
            $targetGroup = ""
            $memberName = ""
            $memberType = "User"
            
            if ($eventTargetType -eq "User") {
                # User created/deleted
                $targetGroup = "SYSTEM"
                $memberName = if ($eventTargetName) { $eventTargetName } else { "" }
                $memberType = "User"
            }
            elseif ($eventTargetType -eq "Group") {
                # Group created/deleted
                $targetGroup = if ($eventTargetName) { $eventTargetName } else { "" }
                $memberName = "SYSTEM"
                $memberType = "Group"
            }
            else {
                # Group membership change
                $targetGroup = if ($eventTargetName) { $eventTargetName } else { "" }
                $memberName = if ($eventMemberName) { $eventMemberName } else { "" }
                $memberType = if ($eventMemberType) { $eventMemberType } else { "User" }
            }
            
            $insertQuery = @"
                INSERT INTO fact.AdGroupEvent (EventTime, DomainControllerId, TargetGroup, MemberName, MemberType, Action, PerformedByUserId, PerformedByRaw, Source)
                VALUES (@EventTime, @DomainControllerId, @TargetGroup, @MemberName, @MemberType, @Action, @PerformedByUserId, @PerformedByRaw, 'PowerShell Script')
"@
            
            $insertCmd = New-Object System.Data.SqlClient.SqlCommand($insertQuery, $connection)
            $insertCmd.Parameters.AddWithValue("@EventTime", $eventEventTime) | Out-Null
            $insertCmd.Parameters.AddWithValue("@DomainControllerId", $serverId) | Out-Null
            $performedByUserIdValue = if ($performedByUserId) { [object]$performedByUserId } else { [DBNull]::Value }
            # Store just username in PerformedByRaw (like in DNS script) - not UPN, not SID
            $performedByRawValue = if ($performedByRawClean) { 
                [string]$performedByRawClean  # Should already be just username
            } else { 
                [DBNull]::Value 
            }
            
            $insertCmd.Parameters.AddWithValue("@TargetGroup", $targetGroup) | Out-Null
            $insertCmd.Parameters.AddWithValue("@MemberName", $memberName) | Out-Null
            $insertCmd.Parameters.AddWithValue("@MemberType", $memberType) | Out-Null
            $insertCmd.Parameters.AddWithValue("@Action", $eventAction) | Out-Null
            $insertCmd.Parameters.AddWithValue("@PerformedByUserId", $performedByUserIdValue) | Out-Null
            $insertCmd.Parameters.AddWithValue("@PerformedByRaw", $performedByRawValue) | Out-Null
            
            $insertCmd.ExecuteNonQuery() | Out-Null
            $groupEventsCount++
        }
        
        $connection.Close()
        Write-Host "Successfully written: $groupEventsCount AD events (users, groups, membership changes)" -ForegroundColor Green
    }
    catch {
        Write-Error "Error writing to database: $_"
    }
}

# Main logic
Write-Host "=== Checking AD changes for the last $HoursBack hours ===" -ForegroundColor Cyan
Write-Host ""

$startTime = (Get-Date).AddHours(-$HoursBack)

# Get list of DCs
if ($UseDefaultControllers) {
    Write-Host "Using default Domain Controllers..." -ForegroundColor Yellow
    $servers = @()
    foreach ($serverName in $defaultDomainControllers) {
        $servers += [PSCustomObject]@{
            ServerId = 0
            ServerName = $serverName
        }
    }
}
elseif ($DomainControllers.Count -gt 0) {
    Write-Host "Using specified Domain Controllers..." -ForegroundColor Yellow
    $servers = @()
    foreach ($serverName in $DomainControllers) {
        # Extract short name from FQDN if needed
        $shortName = $serverName
        if ($serverName -match '^([^.]+)') {
            $shortName = $matches[1]
        }
        $servers += [PSCustomObject]@{
            ServerId = 0
            ServerName = $shortName
        }
    }
}
else {
    Write-Host "Using default DC list (<DOMAIN_CONTROLLER>, <DOMAIN_CONTROLLER>, <DOMAIN_CONTROLLER>, <DOMAIN_CONTROLLER>, <DOMAIN_CONTROLLER>, <DOMAIN_CONTROLLER>, <DOMAIN_CONTROLLER>)" -ForegroundColor Yellow
    $servers = @()
    foreach ($serverName in $defaultDomainControllers) {
        $servers += [PSCustomObject]@{
            ServerId = 0
            ServerName = $serverName
        }
    }
    
    # Write-Host "Getting list of Domain Controllers from database..." -ForegroundColor Yellow
    # $servers = Get-DomainControllersFromDatabase -ConnString $ConnectionString
    # 
    # if ($servers.Count -eq 0) {
    #     # Try to get DCs from AD
    #     Write-Host "Searching for DCs in Active Directory..." -ForegroundColor Yellow
    #     $dcs = Get-ADDomainController -Filter * | Select-Object -ExpandProperty HostName
    #     $adServers = @()
    #     foreach ($dc in $dcs) {
    #         # Extract short name from FQDN
    #         $shortName = $dc
    #         if ($dc -match '^([^.]+)') {
    #             $shortName = $matches[1]
    #         }
    #         $adServers += [PSCustomObject]@{
    #             ServerId = 0
    #             ServerName = $shortName
    #         }
    #     }
    #     $servers = $adServers
    #     
    #     # If still no DCs found, use default list
    #     if ($servers.Count -eq 0) {
    #         Write-Host "No DCs found. Using default list..." -ForegroundColor Yellow
    #         $defaultServers = @()
    #         foreach ($serverName in $defaultDomainControllers) {
    #             $defaultServers += [PSCustomObject]@{
    #                 ServerId = 0
    #                 ServerName = $serverName
    #             }
    #         }
    #         $servers = $defaultServers
    #     }
    # }
}

if ($servers.Count -eq 0) {
    Write-Warning "No Domain Controllers found for checking"
    exit 1
}

Write-Host "Found DCs: $($servers.Count)" -ForegroundColor Green
Write-Host "Check period: from $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Yellow
Write-Host ""

# Collect results
$allEvents = @()
$successCount = 0
$failCount = 0

foreach ($server in $servers) {
    $serverName = $server.ServerName
    $serverId = $server.ServerId
    
    Write-Host "Checking DC: $serverName..." -ForegroundColor Cyan
    
    $events = Get-AdEventsFromServer -ServerName $serverName -ServerId $serverId -StartTime $startTime
    
    if ($events.Count -gt 0) {
        $allEvents += $events
        $successCount++
        Write-Host "  ✓ Found events: $($events.Count)" -ForegroundColor Green
    }
    else {
        $failCount++
        Write-Host "  - No events found" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "=== Results ===" -ForegroundColor Cyan
Write-Host "DCs checked: $($servers.Count)" -ForegroundColor Green
Write-Host "Total events: $($allEvents.Count)" -ForegroundColor Yellow
Write-Host ""

# Write to database
if ($allEvents.Count -gt 0) {
    Write-Host "Writing results to database..." -ForegroundColor Yellow
    Write-AdEventsToDatabase -Events $allEvents -ConnString $ConnectionString
}

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Green

