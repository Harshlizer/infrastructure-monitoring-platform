# Sanitized sample from an internal infrastructure monitoring project.
# Secrets, internal identifiers, and localized text have been removed or generalized.

param(
    [string]$ConnectionString = "Server=<SQL_SERVER>;Database=<MONITORING_DATABASE>;User ID=<SQL_USERNAME>;Password=<SQL_PASSWORD>;TrustServerCertificate=True;",
    [int]$HoursBack = 24,
    [string]$ServerName = $env:COMPUTERNAME
)

function Get-OrCreateServer {
    param(
        [string]$ServerName,
        [System.Data.SqlClient.SqlConnection]$Connection
    )
    
    try {
        $findQuery = "SELECT ServerId FROM dim.Server WHERE ServerName = @ServerName"
        $findCmd = New-Object System.Data.SqlClient.SqlCommand($findQuery, $Connection)
        $findCmd.Parameters.AddWithValue("@ServerName", $ServerName) | Out-Null
        $serverIdObj = $findCmd.ExecuteScalar()
        
        if ($serverIdObj) {
            return [int]$serverIdObj
        }
        
        $insertServerQuery = @"
            INSERT INTO dim.Server (ServerName, Role, IsActive, CreatedAt)
            OUTPUT INSERTED.ServerId
            VALUES (@ServerName, 'DNS', 1, GETUTCDATE())
"@
        $insertCmd = New-Object System.Data.SqlClient.SqlCommand($insertServerQuery, $Connection)
        $insertCmd.Parameters.AddWithValue("@ServerName", $ServerName) | Out-Null
        $serverId = [int]$insertCmd.ExecuteScalar()
        Write-Host "Sanitized status message" -ForegroundColor Green
        return $serverId
    }
    catch {
        Write-Warning "Sanitized status message"
        return $null
    }
}

function Convert-SIDToUserName {
    param([string]$SID)
    try {
        $user = (New-Object System.Security.Principal.SecurityIdentifier($SID)).Translate([System.Security.Principal.NTAccount]).Value
        $username = $user.Split('\')[-1]  #   ,  
        return $username
    }
    catch {
        return $SID
    }
}

function Get-DnsEventsLocal {
    param([DateTime]$StartTime)
    
    $events = @()
    
    try {
        $winEvents = Get-WinEvent -FilterHashtable @{
            LogName = 'Microsoft-Windows-DNSServer/Audit'
            Id = @(512, 513, 515, 516)
            StartTime = $StartTime
        } -ErrorAction SilentlyContinue
        
        if (-not $winEvents) {
            Write-Host "Sanitized status message" -ForegroundColor Yellow
            return $events
        }
        
        Write-Host "Sanitized status message" -ForegroundColor Green
        
        foreach ($winEvent in $winEvents) {
            $action = switch ($winEvent.Id) {
                512 { "Created" }
                513 { "Deleted" }
                515 { "Created" }
                516 { "Deleted" }
                default { "Unknown" }
            }
            
            $eventType = if ($winEvent.Id -eq 512 -or $winEvent.Id -eq 513) { "Zone" } else { "Record" }
            
            $nameValue = ""
            if ($winEvent.Properties.Count -gt 1) {
                $nameValue = $winEvent.Properties[1].Value
            }
            
            $zoneName = ""
            $recordName = ""
            $recordType = ""
            
            if ($eventType -eq "Zone") {
                if ($winEvent.Message) {
                    if ($winEvent.Message -match "zone\s+([a-zA-Z0-9][a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,})") {
                        $zoneName = $matches[1]
                    }
                    elseif ($winEvent.Message -match "zone\s+['""]([^'""]+)['""]") {
                        $zoneName = $matches[1]
                    }
                }
                if (-not $zoneName) {
                    $zoneName = $nameValue
                }
            }
            else {
                $recordName = $nameValue
                
                if ($winEvent.Message) {
                    if ($winEvent.Message -match "zone\s+([a-zA-Z0-9][a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,})") {
                        $zoneName = $matches[1]
                    }
                }
                
                if ($winEvent.Message) {
                    if ($winEvent.Message -match "type\s+(\d+)") {
                        $typeNum = $matches[1]
                        $recordType = switch ($typeNum) {
                            "1" { "A" }
                            "2" { "NS" }
                            "5" { "CNAME" }
                            "12" { "PTR" }
                            "15" { "MX" }
                            "16" { "TXT" }
                            default { "Type$typeNum" }
                        }
                    }
                }
            }
            
            $performedBy = ""
            if ($winEvent.UserId) {
                $performedBy = Convert-SIDToUserName -SID $winEvent.UserId
            }
            
            $cleanMessage = $winEvent.Message
            if ($cleanMessage) {
                $cleanMessage = $cleanMessage -replace " TTL \d+ and RDATA \w+", ""
                $cleanMessage = $cleanMessage -replace "\[virtualization instance: \.\]", ""
                $cleanMessage = $cleanMessage.Trim()
            }
            
            $events += @{
                EventTime = $winEvent.TimeCreated
                Action = $action
                EventType = $eventType
                ZoneName = $zoneName
                RecordName = $recordName
                RecordType = $recordType
                PerformedBy = $performedBy
                Message = $cleanMessage
            }
        }
    }
    catch {
        Write-Warning "Sanitized status message"
    }
    
    return $events
}

function Write-DnsEventsToDatabase {
    param(
        [array]$Events,
        [string]$ConnString,
        [int]$ServerId
    )
    
    if ($Events.Count -eq 0) {
        Write-Warning "Sanitized status message"
        return
    }
    
    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection($ConnString)
        $connection.Open()
        
        $zoneEventsCount = 0
        $recordEventsCount = 0
        
        foreach ($event in $Events) {
            if ($event.EventType -eq "Zone") {
                $insertQuery = @"
                    INSERT INTO fact.DnsZoneEvent (EventTime, ServerId, ZoneName, Action, PerformedBy, Message)
                    VALUES (@EventTime, @ServerId, @ZoneName, @Action, @PerformedBy, @Message)
"@
                
                $zoneName = if ($event.ZoneName) { $event.ZoneName } else { "" }
                $performedBy = if ($event.PerformedBy) { [object]$event.PerformedBy } else { [DBNull]::Value }
                $message = if ($event.Message) { $event.Message } else { [DBNull]::Value }
                
                $insertCmd = New-Object System.Data.SqlClient.SqlCommand($insertQuery, $connection)
                $insertCmd.Parameters.AddWithValue("@EventTime", $event.EventTime) | Out-Null
                $insertCmd.Parameters.AddWithValue("@ServerId", $ServerId) | Out-Null
                $insertCmd.Parameters.AddWithValue("@ZoneName", $zoneName) | Out-Null
                $insertCmd.Parameters.AddWithValue("@Action", $event.Action) | Out-Null
                $insertCmd.Parameters.AddWithValue("@PerformedBy", $performedBy) | Out-Null
                $insertCmd.Parameters.AddWithValue("@Message", $message) | Out-Null
                
                $insertCmd.ExecuteNonQuery() | Out-Null
                $zoneEventsCount++
            }
            else {
                $insertQuery = @"
                    INSERT INTO fact.DnsRecordEvent (EventTime, ServerId, ZoneName, RecordName, RecordType, Action, PerformedBy, Message)
                    VALUES (@EventTime, @ServerId, @ZoneName, @RecordName, @RecordType, @Action, @PerformedBy, @Message)
"@
                
                $zoneName = if ($event.ZoneName) { $event.ZoneName } else { "" }
                $recordName = if ($event.RecordName) { $event.RecordName } else { "" }
                $recordType = if ($event.RecordType) { $event.RecordType } else { "" }
                $performedBy = if ($event.PerformedBy) { [object]$event.PerformedBy } else { [DBNull]::Value }
                $message = if ($event.Message) { $event.Message } else { [DBNull]::Value }
                
                $insertCmd = New-Object System.Data.SqlClient.SqlCommand($insertQuery, $connection)
                $insertCmd.Parameters.AddWithValue("@EventTime", $event.EventTime) | Out-Null
                $insertCmd.Parameters.AddWithValue("@ServerId", $ServerId) | Out-Null
                $insertCmd.Parameters.AddWithValue("@ZoneName", $zoneName) | Out-Null
                $insertCmd.Parameters.AddWithValue("@RecordName", $recordName) | Out-Null
                $insertCmd.Parameters.AddWithValue("@RecordType", $recordType) | Out-Null
                $insertCmd.Parameters.AddWithValue("@Action", $event.Action) | Out-Null
                $insertCmd.Parameters.AddWithValue("@PerformedBy", $performedBy) | Out-Null
                $insertCmd.Parameters.AddWithValue("@Message", $message) | Out-Null
                
                $insertCmd.ExecuteNonQuery() | Out-Null
                $recordEventsCount++
            }
        }
        
        $connection.Close()
        Write-Host "Sanitized status message" -ForegroundColor Green
    }
    catch {
        Write-Error "Sanitized status message"
    }
}

Write-Host "Sanitized status message" -ForegroundColor Cyan
Write-Host "Sanitized status message" -ForegroundColor Yellow
Write-Host ""

$startTime = (Get-Date).AddHours(-$HoursBack)
Write-Host "Sanitized status message" -ForegroundColor Yellow
Write-Host ""

Write-Host "Sanitized status message" -ForegroundColor Cyan
$allEvents = Get-DnsEventsLocal -StartTime $startTime

if ($allEvents.Count -eq 0) {
    Write-Host "Sanitized status message" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Sanitized status message" -ForegroundColor Green
    exit 0
}

Write-Host "Sanitized status message" -ForegroundColor Green
Write-Host ""

Write-Host "Sanitized status message" -ForegroundColor Cyan
try {
    $connection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
    $connection.Open()
    
    $serverId = Get-OrCreateServer -ServerName $ServerName -Connection $connection
    
    if (-not $serverId) {
        Write-Error "Sanitized status message"
        $connection.Close()
        exit 1
    }
    
    Write-Host "Sanitized status message" -ForegroundColor Yellow
    Write-DnsEventsToDatabase -Events $allEvents -ConnString $ConnectionString -ServerId $serverId
    
    $connection.Close()
}
catch {
    Write-Error "Sanitized status message"
    exit 1
}

Write-Host ""
Write-Host "Sanitized status message" -ForegroundColor Green

