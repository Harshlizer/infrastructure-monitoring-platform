# Sanitized sample from an internal infrastructure monitoring project.
# Secrets, internal identifiers, and localized text have been removed or generalized.

param(
    [string]$ConnectionString = "Server=<SQL_SERVER>;Database=<MONITORING_DATABASE>;User ID=<SQL_USERNAME>;Password=<SQL_PASSWORD>;TrustServerCertificate=True;"
)

$serverName = $env:COMPUTERNAME

Write-Host "Sanitized status message" -ForegroundColor Cyan
Write-Host "Sanitized status message" -ForegroundColor Yellow

try {
    $shutdownEvent = Get-WinEvent -FilterHashtable @{LogName='System'; ID=6006} -MaxEvents 1 -ErrorAction SilentlyContinue
    $startupEvent = Get-WinEvent -FilterHashtable @{LogName='System'; ID=6005} -MaxEvents 1 -ErrorAction SilentlyContinue
    
    $shutdown = if ($shutdownEvent) { $shutdownEvent.TimeCreated } else { $null }
    $startup = if ($startupEvent) { $startupEvent.TimeCreated } else { $null }
    
    Write-Host "Sanitized status message" -ForegroundColor Yellow
    Write-Host "Sanitized status message" -ForegroundColor Yellow
}
catch {
    Write-Warning "Sanitized status message"
    $shutdown = $null
    $startup = $null
}

$user = $null
$reason = $null
try {
    $event1074 = Get-WinEvent -FilterHashtable @{LogName='System'; ID=1074} -MaxEvents 1 -ErrorAction SilentlyContinue
    if ($event1074) {
        $user = ($event1074.Properties[6].Value) -replace '^.*\\'  #  
        $reason = $event1074.Properties[4].Value
        Write-Host "Sanitized status message" -ForegroundColor Yellow
        Write-Host "Sanitized status message" -ForegroundColor Yellow
    }
}
catch {
    Write-Warning "Sanitized status message"
}

if (-not $startup) {
    Write-Warning "Sanitized status message"
    exit 0
}

try {
    $connection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
    $connection.Open()
    
    Write-Host "Sanitized status message" -ForegroundColor Green
    
    $getServerQuery = @"
        SELECT ServerId FROM dim.Server WHERE ServerName = @ServerName
"@
    $getServerCmd = New-Object System.Data.SqlClient.SqlCommand($getServerQuery, $connection)
    $getServerCmd.Parameters.AddWithValue("@ServerName", $serverName) | Out-Null
    $serverIdObj = $getServerCmd.ExecuteScalar()
    
    $serverId = 0
    if ($serverIdObj) {
        $serverId = [int]$serverIdObj
        Write-Host "Sanitized status message" -ForegroundColor Green
    }
    else {
        $insertServerQuery = @"
            INSERT INTO dim.Server (ServerName, IsActive, CreatedAt)
            OUTPUT INSERTED.ServerId
            VALUES (@ServerName, 1, GETUTCDATE())
"@
        $insertServerCmd = New-Object System.Data.SqlClient.SqlCommand($insertServerQuery, $connection)
        $insertServerCmd.Parameters.AddWithValue("@ServerName", $serverName) | Out-Null
        $serverId = [int]$insertServerCmd.ExecuteScalar()
        Write-Host "Sanitized status message" -ForegroundColor Green
    }
    
    $checkQuery = @"
        SELECT COUNT(*) FROM fact.ServerReboot 
        WHERE ServerId = @ServerId AND BootTime = @BootTime
"@
    $checkCmd = New-Object System.Data.SqlClient.SqlCommand($checkQuery, $connection)
    $checkCmd.Parameters.AddWithValue("@ServerId", $serverId) | Out-Null
    $checkCmd.Parameters.AddWithValue("@BootTime", $startup) | Out-Null
    $exists = [int]$checkCmd.ExecuteScalar()
    
    if ($exists -gt 0) {
        Write-Host "Sanitized status message" -ForegroundColor Yellow
        $connection.Close()
        exit 0
    }
    
    $userId = $null
    if ($user) {
        $getUserQuery = @"
            SELECT UserId FROM dim.[User] WHERE UPN = @UPN
"@
        $getUserCmd = New-Object System.Data.SqlClient.SqlCommand($getUserQuery, $connection)
        $getUserCmd.Parameters.AddWithValue("@UPN", "$user@aventusgroup.local") | Out-Null
        $userIdObj = $getUserCmd.ExecuteScalar()
        
        if ($userIdObj) {
            $userId = [int]$userIdObj
        }
        else {
            $insertUserQuery = @"
                INSERT INTO dim.[User] (UPN, DisplayName, CreatedAt)
                OUTPUT INSERTED.UserId
                VALUES (@UPN, @DisplayName, GETUTCDATE())
"@
            $insertUserCmd = New-Object System.Data.SqlClient.SqlCommand($insertUserQuery, $connection)
            $insertUserCmd.Parameters.AddWithValue("@UPN", "$user@aventusgroup.local") | Out-Null
            $insertUserCmd.Parameters.AddWithValue("@DisplayName", $user) | Out-Null
            $userId = [int]$insertUserCmd.ExecuteScalar()
            Write-Host "Sanitized status message" -ForegroundColor Green
        }
    }
    
    $checkColumnQuery = @"
        SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS 
        WHERE TABLE_SCHEMA = 'fact' 
        AND TABLE_NAME = 'ServerReboot' 
        AND COLUMN_NAME = 'ShutdownTime'
"@
    $checkColumnCmd = New-Object System.Data.SqlClient.SqlCommand($checkColumnQuery, $connection)
    $hasShutdownTime = [int]$checkColumnCmd.ExecuteScalar() -gt 0
    
    if ($hasShutdownTime) {
        $insertQuery = @"
            INSERT INTO fact.ServerReboot (
                ServerId, 
                BootTime, 
                ShutdownTime,
                Reason, 
                InitiatedByUserId, 
                InitiatedByRaw, 
                Source
            )
            VALUES (
                @ServerId, 
                @BootTime, 
                @ShutdownTime,
                @Reason, 
                @InitiatedByUserId, 
                @InitiatedByRaw, 
                @Source
            )
"@
        $insertCmd = New-Object System.Data.SqlClient.SqlCommand($insertQuery, $connection)
        $insertCmd.Parameters.AddWithValue("@ServerId", $serverId) | Out-Null
        $insertCmd.Parameters.AddWithValue("@BootTime", $startup) | Out-Null
        if ($shutdown) {
            $insertCmd.Parameters.AddWithValue("@ShutdownTime", $shutdown) | Out-Null
        } else {
            $insertCmd.Parameters.AddWithValue("@ShutdownTime", [DBNull]::Value) | Out-Null
        }
        
        if ($reason) {
            $insertCmd.Parameters.AddWithValue("@Reason", $reason) | Out-Null
        } else {
            $insertCmd.Parameters.AddWithValue("@Reason", [DBNull]::Value) | Out-Null
        }
        
        if ($userId) {
            $insertCmd.Parameters.AddWithValue("@InitiatedByUserId", $userId) | Out-Null
        } else {
            $insertCmd.Parameters.AddWithValue("@InitiatedByUserId", [DBNull]::Value) | Out-Null
        }
        
        if ($user) {
            $insertCmd.Parameters.AddWithValue("@InitiatedByRaw", $user) | Out-Null
        } else {
            $insertCmd.Parameters.AddWithValue("@InitiatedByRaw", [DBNull]::Value) | Out-Null
        }
        
        $insertCmd.Parameters.AddWithValue("@Source", "PowerShell Script (ServerRebootReporter)") | Out-Null
    }
    else {
        $insertQuery = @"
            INSERT INTO fact.ServerReboot (
                ServerId, 
                BootTime, 
                Reason, 
                InitiatedByUserId, 
                InitiatedByRaw, 
                Source
            )
            VALUES (
                @ServerId, 
                @BootTime, 
                @Reason, 
                @InitiatedByUserId, 
                @InitiatedByRaw, 
                @Source
            )
"@
        $insertCmd = New-Object System.Data.SqlClient.SqlCommand($insertQuery, $connection)
        $insertCmd.Parameters.AddWithValue("@ServerId", $serverId) | Out-Null
        $insertCmd.Parameters.AddWithValue("@BootTime", $startup) | Out-Null
        $reasonText = if ($reason) { $reason } else { "" }
        if ($shutdown) {
            $reasonText = "Shutdown: $shutdown. $reasonText".Trim()
        }
        
        if ($reasonText) {
            $insertCmd.Parameters.AddWithValue("@Reason", $reasonText) | Out-Null
        } else {
            $insertCmd.Parameters.AddWithValue("@Reason", [DBNull]::Value) | Out-Null
        }
        
        if ($userId) {
            $insertCmd.Parameters.AddWithValue("@InitiatedByUserId", $userId) | Out-Null
        } else {
            $insertCmd.Parameters.AddWithValue("@InitiatedByUserId", [DBNull]::Value) | Out-Null
        }
        
        if ($user) {
            $insertCmd.Parameters.AddWithValue("@InitiatedByRaw", $user) | Out-Null
        } else {
            $insertCmd.Parameters.AddWithValue("@InitiatedByRaw", [DBNull]::Value) | Out-Null
        }
        
        $insertCmd.Parameters.AddWithValue("@Source", "PowerShell Script (ServerRebootReporter)") | Out-Null
    }
    
    $insertCmd.ExecuteNonQuery() | Out-Null
    Write-Host "Sanitized status message" -ForegroundColor Green
    
    $connection.Close()
}
catch {
    Write-Error "Sanitized status message"
    exit 1
}

Write-Host "Sanitized status message" -ForegroundColor Green

