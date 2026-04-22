# Sanitized sample from an internal infrastructure monitoring project.
# Secrets, internal identifiers, and localized text have been removed or generalized.

# Script for checking SQL Server backups in GCP buckets
# Writes results to Monitoring database

param(
    [string]$ConnectionString = "Server=<SQL_SERVER>;Database=<MONITORING_DATABASE>;User ID=<SQL_USERNAME>;Password=<SQL_PASSWORD>;TrustServerCertificate=True;",
    [int]$DaysBack = 1  #     N 
)


$serverConfigs = @(
    @{
        ServerName = "<SERVER_NAME>"
        ServerIp = "<INTERNAL_IP>"
        ProjectName = "acredit"
        GcpProjectId = "<SERVER_NAME>"
        CredentialsPath = "<SERVICE_ACCOUNT_KEY_DIRECTORY>\\<SERVER_NAME>.json"
    },
    @{
        ServerName = "<SERVER_NAME>"
        ServerIp = "<INTERNAL_IP>"
        ProjectName = "onecredit"
        GcpProjectId = "<SERVER_NAME>"
        CredentialsPath = "<SERVICE_ACCOUNT_KEY_DIRECTORY>\\<SERVER_NAME>.json"
    },
    @{
        ServerName = "<SERVER_NAME>"
        ServerIp = "<INTERNAL_IP>"
        ProjectName = "credit365"
        GcpProjectId = "<SERVER_NAME>"
        CredentialsPath = "<SERVICE_ACCOUNT_KEY_DIRECTORY>\\<SERVER_NAME>.json"
    },
    @{
        ServerName = "<SERVER_NAME>"
        ServerIp = "<INTERNAL_IP>"
        ProjectName = "creditplus"
        GcpProjectId = "<SERVER_NAME>"
        CredentialsPath = "<SERVICE_ACCOUNT_KEY_DIRECTORY>\\<SERVER_NAME>.json"
    },
    @{
        ServerName = "<SERVER_NAME>"
        ServerIp = "<INTERNAL_IP>"
        ProjectName = "findom"
        GcpProjectId = "<SERVER_NAME>"
        CredentialsPath = "<SERVICE_ACCOUNT_KEY_DIRECTORY>\\<SERVER_NAME>.json"
    },
    @{
        ServerName = "<SERVER_NAME>"
        ServerIp = "<INTERNAL_IP>"
        ProjectName = "ecommoney"
        GcpProjectId = "<SERVER_NAME>"
        CredentialsPath = "<SERVICE_ACCOUNT_KEY_DIRECTORY>\\<SERVER_NAME>.json"
    },
    @{
        ServerName = "<SERVER_NAME>"
        ServerIp = "<INTERNAL_IP>"
        ProjectName = "beeclever"
        GcpProjectId = "<SERVER_NAME>"
        CredentialsPath = "<SERVICE_ACCOUNT_KEY_DIRECTORY>\\<SERVER_NAME>.json"
    },
    @{
        ServerName = "<SERVER_NAME>"
        ServerIp = "<INTERNAL_IP>"
        ProjectName = "eco_creditline"
        GcpProjectId = "<SERVER_NAME>"
        CredentialsPath = "<SERVICE_ACCOUNT_KEY_DIRECTORY>\\<SERVER_NAME>.json"
    },
    @{
        ServerName = "<SERVER_NAME>"
        ServerIp = "<INTERNAL_IP>"
        ProjectName = "1c-ua"
        GcpProjectId = "<SERVER_NAME>"
        CredentialsPath = "<SERVICE_ACCOUNT_KEY_DIRECTORY>\\<SERVER_NAME>.json"
    },
    @{
        ServerName = "<SERVER_NAME>"
        ServerIp = "<INTERNAL_IP>"
        ProjectName = "1c-ua"
        GcpProjectId = "<SERVER_NAME>"
        CredentialsPath = "<SERVICE_ACCOUNT_KEY_DIRECTORY>\\<SERVER_NAME>.json"
    }
)

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
            VALUES (@ServerName, 'SQL Server', 1, GETDATE());
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

function Get-SqlDatabases {
    param(
        [string]$ServerName
    )
    
    try {
        if (-not (Test-Connection -ComputerName $ServerName -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
            Write-Host "Sanitized status message" -ForegroundColor Gray
            return @()
        }
        
        $query = "SELECT name FROM sys.databases WHERE state = 0 AND name NOT IN ('master', 'tempdb', 'model', 'msdb')"
        $databases = Invoke-Sqlcmd -ServerInstance $ServerName -Query $query -ErrorAction SilentlyContinue
        
        if ($databases) {
            $dbNames = $databases | ForEach-Object { $_.name }
            Write-Host "Sanitized status message" -ForegroundColor Gray
            return $dbNames
        }
        return @()
    }
    catch {
        Write-Host "Sanitized status message" -ForegroundColor Gray
        return @()
    }
}

function Get-GcpAccessToken {
    param(
        [string]$CredentialsPath
    )
    
    try {
        if (Get-Command gcloud -ErrorAction SilentlyContinue) {
            $env:GOOGLE_APPLICATION_CREDENTIALS = $CredentialsPath
            $token = gcloud auth application-default print-access-token 2>$null
            if ($token) {
                return $token.Trim()
            }
        }
        
        Write-Warning "Sanitized status message"
        return $null
    }
    catch {
        Write-Warning "Sanitized status message"
        return $null
    }
}

function Get-BackupsFromGcpBucket {
    param(
        [string]$BucketName,
        [string]$CredentialsPath,
        [string]$GcpProjectId,
        [string]$ServerName,
        [DateTime]$StartDate
    )
    
    $backups = @()
    
    try {
        $env:GOOGLE_APPLICATION_CREDENTIALS = $CredentialsPath
        
        $allObjects = @()
        
        $gsutilCmd = Get-Command gsutil -ErrorAction SilentlyContinue
        if ($gsutilCmd) {
            Write-Host "Sanitized status message" -ForegroundColor Gray
            Write-Host "Sanitized status message" -ForegroundColor DarkGray
            
            try {
                $env:GOOGLE_APPLICATION_CREDENTIALS = $CredentialsPath
                
                Write-Host "Sanitized status message" -ForegroundColor DarkGray
                $output = & gsutil ls -l "gs://$BucketName/**" 2>&1
                
                if ($LASTEXITCODE -eq 0 -and $output) {
                    Write-Host "Sanitized status message" -ForegroundColor DarkGray
                    
                    foreach ($line in $output) {
                        if ([string]::IsNullOrWhiteSpace($line)) { continue }
                        
                        if ($line -match "^\s*(\d+)\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})\s+gs://([^/]+)/(.+)$") {
                            $size = [long]$matches[1]
                            $dateStr = $matches[2]
                            $timeStr = $matches[3]
                            $bucketFromLine = $matches[4]
                            $objectPath = $matches[5]
                            
                            if ($bucketFromLine -eq $BucketName) {
                                try {
                                    $timeCreated = [DateTime]::Parse("$dateStr $timeStr")
                                    
                                    $allObjects += [PSCustomObject]@{
                                        name = $objectPath
                                        timeCreated = $timeCreated
                                        size = $size
                                    }
                                }
                                catch {
                                }
                            }
                        }
                        elseif ($line -match "^\s*gs://([^/]+)/(.+)$") {
                            $bucketFromLine = $matches[1]
                            $objectPath = $matches[2]
                            
                            if ($bucketFromLine -eq $BucketName) {
                                try {
                                    $statOutput = & gsutil stat "gs://$BucketName/$objectPath" 2>&1
                                    if ($LASTEXITCODE -eq 0) {
                                        $timeCreated = $null
                                        $size = $null
                                        
                                        foreach ($statLine in $statOutput) {
                                            if ($statLine -match "Time created:\s*(.+)") {
                                                try {
                                                    $timeCreated = [DateTime]::Parse($matches[1].Trim())
                                                }
                                                catch { }
                                            }
                                            if ($statLine -match "Content-Length:\s*(\d+)") {
                                                $size = [long]$matches[1]
                                            }
                                        }
                                        
                                        if ($timeCreated) {
                                            $allObjects += [PSCustomObject]@{
                                                name = $objectPath
                                                timeCreated = $timeCreated
                                                size = $size
                                            }
                                        }
                                    }
                                }
                                catch {
                                }
                            }
                        }
                    }
                }
                elseif ($LASTEXITCODE -ne 0) {
                    Write-Warning "Sanitized status message"
                    $errorOutput = $output | Where-Object { $_ -match "error|Error|ERROR|denied|Denied|DENIED" }
                    if ($errorOutput) {
                        Write-Host "Sanitized status message" -ForegroundColor Yellow
                    }
                }
            }
            catch {
                Write-Warning "Sanitized status message"
            }
        }
        
        if ($allObjects.Count -eq 0) {
            $accessToken = Get-GcpAccessToken -CredentialsPath $CredentialsPath
            if ($accessToken) {
                Write-Host "Sanitized status message" -ForegroundColor Gray
                
                $headers = @{
                    "Authorization" = "Bearer $accessToken"
                }
                
                $uri = "https://storage.googleapis.com/storage/v1/b/$BucketName/o"
                $pageToken = $null
                
                do {
                    $params = @{}
                    if ($pageToken) {
                        $params["pageToken"] = $pageToken
                    }
                    
                    $queryString = ($params.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "&"
                    $fullUri = if ($queryString) { "$uri?$queryString" } else { $uri }
                    
                    try {
                        $response = Invoke-RestMethod -Uri $fullUri -Headers $headers -Method Get -ErrorAction Stop
                        if ($response.items) {
                            foreach ($item in $response.items) {
                                $allObjects += [PSCustomObject]@{
                                    name = $item.name
                                    timeCreated = if ($item.timeCreated) { [DateTime]::Parse($item.timeCreated) } else { $null }
                                    size = if ($item.size) { [long]$item.size } else { $null }
                                }
                            }
                        }
                        $pageToken = $response.nextPageToken
                    }
                    catch {
                        Write-Warning "Sanitized status message"
                        break
                    }
                } while ($pageToken)
            }
            else {
                Write-Warning "Sanitized status message"
                Write-Host "Sanitized status message" -ForegroundColor Yellow
                return $backups
            }
        }
        else {
            Write-Warning "Sanitized status message"
            Write-Host "Sanitized status message" -ForegroundColor Yellow
            return $backups
        }
        
        Write-Host "Sanitized status message" -ForegroundColor Gray
        Write-Host "Sanitized status message" -ForegroundColor Gray
        
        foreach ($obj in $allObjects) {
            $createdDate = $obj.timeCreated
            if (-not $createdDate) {
                continue  #    
            }
            
            if ($createdDate -ge $StartDate) {
                $fileName = $obj.name
                
                $dbName = "Unknown"
                if ($fileName -match ".*[\\/]([^\\/]+)_(\d{8})\.bak") {
                    $dbName = $matches[1]
                }
                elseif ($fileName -match ".*[\\/]([^\\/]+)\.bak") {
                    $dbName = $matches[1]
                }
                elseif ($fileName -match ".*[\\/]([^\\/]+)_(\d{4}-\d{2}-\d{2})\.bak") {
                    $dbName = $matches[1]
                }
                
                $backups += [PSCustomObject]@{
                    ServerName = $ServerName
                    DatabaseName = $dbName
                    BackupDate = $createdDate
                    BucketName = $BucketName
                    FileName = $fileName
                    FileSize = $obj.size
                    UploadedDate = $createdDate
                    IsUploaded = $true
                    GcpProjectId = $GcpProjectId
                }
            }
        }
        
        Write-Host "Sanitized status message" -ForegroundColor Green
    }
    catch {
        Write-Warning "Sanitized status message"
    }
    
    return $backups
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

$startDate = (Get-Date).AddDays(-$DaysBack)
Write-Host "Sanitized status message" -ForegroundColor Cyan
Write-Host "Sanitized status message" -ForegroundColor Yellow

$deleteDate = (Get-Date).AddDays(-($DaysBack + 1))
$deleteQuery = @"
    DELETE FROM fact.BackupGcpBucket 
    WHERE CheckTime < @DeleteDate
"@
$deleteCmd = New-Object System.Data.SqlClient.SqlCommand($deleteQuery, $connection)
$deleteCmd.Parameters.AddWithValue("@DeleteDate", $deleteDate) | Out-Null
$deletedRows = $deleteCmd.ExecuteNonQuery()
Write-Host "Sanitized status message" -ForegroundColor Yellow

$insertQuery = @"
    INSERT INTO fact.BackupGcpBucket (
        ServerId,
        ServerName,
        DatabaseName,
        BackupDate,
        BucketName,
        FileName,
        FileSize,
        UploadedDate,
        IsUploaded,
        GcpProjectId,
        CheckTime,
        Source
    )
    VALUES (
        @ServerId,
        @ServerName,
        @DatabaseName,
        @BackupDate,
        @BucketName,
        @FileName,
        @FileSize,
        @UploadedDate,
        @IsUploaded,
        @GcpProjectId,
        @CheckTime,
        @Source
    )
"@

$insertCmd = New-Object System.Data.SqlClient.SqlCommand($insertQuery, $connection)
$insertedCount = 0
$totalBackups = 0

Write-Host "Sanitized status message" -ForegroundColor Cyan
foreach ($config in $serverConfigs) {
    Write-Host "Sanitized status message" -ForegroundColor Gray
}

$serversByProject = $serverConfigs | Group-Object -Property GcpProjectId

Write-Host "Sanitized status message" -ForegroundColor Cyan
foreach ($pg in $serversByProject) {
    Write-Host "Sanitized status message" -ForegroundColor Gray
    foreach ($srv in $pg.Group) {
        Write-Host "    - $($srv.ServerName)" -ForegroundColor DarkGray
    }
}

foreach ($projectGroup in $serversByProject) {
    $gcpProjectId = $projectGroup.Name
    
    Write-Host "Sanitized status message" -ForegroundColor Magenta
    Write-Host "Sanitized status message" -ForegroundColor Yellow
    Write-Host "Sanitized status message" -ForegroundColor Yellow
    
    if ([string]::IsNullOrWhiteSpace($gcpProjectId)) {
        Write-Warning "Sanitized status message"
        Write-Host "Sanitized status message" -ForegroundColor Red
        continue
    }
    
    $servers = $projectGroup.Group
    
    if ($servers.Count -eq 0) {
        Write-Warning "Sanitized status message"
        continue
    }
    
    $credentialsPath = $servers[0].CredentialsPath
    
    Write-Host "Sanitized status message" -ForegroundColor Gray
    Write-Host "Credentials path: $credentialsPath" -ForegroundColor Gray
    
    if (-not (Test-Path $credentialsPath)) {
        Write-Warning "Sanitized status message"
        Write-Host "Sanitized status message" -ForegroundColor Red
        continue
    }
    
    $bucketName = $gcpProjectId
    
    Write-Host "Sanitized status message" -ForegroundColor Cyan
    Write-Host "Bucket: $bucketName" -ForegroundColor Cyan
    Write-Host "Sanitized status message" -ForegroundColor Cyan
    
    $backups = Get-BackupsFromGcpBucket -BucketName $bucketName -CredentialsPath $credentialsPath -GcpProjectId $gcpProjectId -ServerName $servers[0].ServerName -StartDate $startDate
    
    foreach ($serverConfig in $servers) {
        $serverName = $serverConfig.ServerName
        
        Write-Host "Sanitized status message" -ForegroundColor Yellow
        
        $serverId = Get-OrCreateServer -ServerName $serverName -ConnString $ConnectionString
        if ($serverId -eq 0) {
            Write-Warning "Sanitized status message"
            continue
        }
        
        $serverBackups = $backups | Where-Object { 
            $_.FileName -like "*$serverName*" -or 
            $_.FileName -like "*$($serverConfig.ProjectName)*" 
        }
        
        if ($serverBackups.Count -eq 0) {
            $serverBackups = $backups
        }
        
        $databases = @()
        try {
            $databases = Get-SqlDatabases -ServerName $serverName
        }
        catch {
            Write-Host "Sanitized status message" -ForegroundColor Gray
        }
        
        foreach ($backup in $serverBackups) {
            $dbName = $backup.DatabaseName
            if ($dbName -eq "Unknown" -and $databases.Count -gt 0) {
                foreach ($db in $databases) {
                    if ($backup.FileName -like "*$db*") {
                        $dbName = $db
                        break
                    }
                }
            }
            
            $insertCmd.Parameters.Clear()
            $insertCmd.Parameters.AddWithValue("@ServerId", $serverId) | Out-Null
            $insertCmd.Parameters.AddWithValue("@ServerName", $serverName) | Out-Null
            $insertCmd.Parameters.AddWithValue("@DatabaseName", $dbName) | Out-Null
            $insertCmd.Parameters.AddWithValue("@BackupDate", $backup.BackupDate) | Out-Null
            $insertCmd.Parameters.AddWithValue("@BucketName", $backup.BucketName) | Out-Null
            $insertCmd.Parameters.AddWithValue("@FileName", $backup.FileName) | Out-Null
            
            if ($backup.FileSize) {
                $insertCmd.Parameters.AddWithValue("@FileSize", $backup.FileSize) | Out-Null
            }
            else {
                $insertCmd.Parameters.AddWithValue("@FileSize", [DBNull]::Value) | Out-Null
            }
            
            if ($backup.UploadedDate) {
                $insertCmd.Parameters.AddWithValue("@UploadedDate", $backup.UploadedDate) | Out-Null
            }
            else {
                $insertCmd.Parameters.AddWithValue("@UploadedDate", [DBNull]::Value) | Out-Null
            }
            
            $insertCmd.Parameters.AddWithValue("@IsUploaded", $backup.IsUploaded) | Out-Null
            $insertCmd.Parameters.AddWithValue("@GcpProjectId", $backup.GcpProjectId) | Out-Null
            $insertCmd.Parameters.AddWithValue("@CheckTime", (Get-Date)) | Out-Null
            $insertCmd.Parameters.AddWithValue("@Source", "Check-BackupGcpBuckets") | Out-Null
            
            try {
                $insertCmd.ExecuteNonQuery() | Out-Null
                $insertedCount++
                $totalBackups++
            }
            catch {
                Write-Warning "Sanitized status message"
            }
        }
        
        Write-Host "Sanitized status message" -ForegroundColor Green
    }
}

$connection.Close()

Write-Host "Sanitized status message" -ForegroundColor Cyan
Write-Host "Sanitized status message" -ForegroundColor Green
Write-Host "Sanitized status message" -ForegroundColor Green
Write-Host "Sanitized status message" -ForegroundColor Green

