# Sanitized sample from an internal infrastructure monitoring project.
# Secrets, internal identifiers, and localized text have been removed or generalized.

param(
    [string]$ConnectionString = "Server=<SQL_SERVER>;Database=<MONITORING_DATABASE>;User ID=<SQL_USERNAME>;Password=<SQL_PASSWORD>;TrustServerCertificate=True;",
    [switch]$UseActiveDirectory = $false,
    [string]$DomainName = $null,
    [PSCredential]$Credential = $null,
    [switch]$UseWMI = $false
)

Import-Module ActiveDirectory -ErrorAction SilentlyContinue

function Get-ServersFromDatabase {
    param([string]$ConnString)
    
    try {
        $query = @"
            SELECT ServerId, ServerName 
            FROM dim.Server 
            WHERE IsActive = 1
            ORDER BY ServerName
"@
        
        $connection = New-Object System.Data.SqlClient.SqlConnection($ConnString)
        $command = New-Object System.Data.SqlClient.SqlCommand($query, $connection)
        $connection.Open()
        
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($command)
        $dataset = New-Object System.Data.DataSet
        $adapter.Fill($dataset) | Out-Null
        
        $servers = @()
        foreach ($row in $dataset.Tables[0].Rows) {
            $servers += @{
                ServerId = $row["ServerId"]
                ServerName = $row["ServerName"]
            }
        }
        
        $connection.Close()
        return $servers
    }
    catch {
        Write-Error "Sanitized status message"
        return @()
    }
}

function Get-ServersFromAD {
    param([string]$Domain)
    
    try {
        if ($Domain) {
            $servers = Get-ADComputer -Filter {OperatingSystem -like "*Windows Server*"} -Server $Domain -Properties Name, DNSHostName | 
                Where-Object { $_.Enabled -eq $true } |
                Select-Object @{Name='ServerId';Expression={0}}, @{Name='ServerName';Expression={$_.DNSHostName -replace '\.\w+\.\w+$',''}}
        }
        else {
            $servers = Get-ADComputer -Filter {OperatingSystem -like "*Windows Server*"} -Properties Name, DNSHostName | 
                Where-Object { $_.Enabled -eq $true } |
                Select-Object @{Name='ServerId';Expression={0}}, @{Name='ServerName';Expression={$_.DNSHostName -replace '\.\w+\.\w+$',''}}
        }
        
        return $servers
    }
    catch {
        Write-Error "Sanitized status message"
        return @()
    }
}

function Get-ServerInfoWMI {
    param(
        [string]$ServerName,
        [PSCredential]$Credential
    )
    
    try {
        $wmiParams = @{
            ComputerName = $ServerName
            ErrorAction = "Stop"
        }
        
        if ($Credential) {
            $wmiParams.Credential = $Credential
        }
        
        $os = Get-CimInstance -ClassName Win32_OperatingSystem @wmiParams
        $osVersion = "$($os.Caption) $($os.Version)"
        
        $roles = @()
        $features = Get-WindowsFeature -ComputerName $ServerName -ErrorAction SilentlyContinue | Where-Object { $_.InstallState -eq "Installed" }
        foreach ($feature in $features) {
            $roles += $feature.Name
        }
        
        $software = @()
        $products = Get-CimInstance -ClassName Win32_Product @wmiParams -ErrorAction SilentlyContinue
        foreach ($product in $products) {
            if ($product.Name -and $product.Version) {
                $software += "$($product.Name) $($product.Version)"
            }
        }
        
        $softwareReg = @()
        try {
            $regParams = @{
                ComputerName = $ServerName
                ErrorAction = "Stop"
            }
            if ($Credential) {
                $regParams.Credential = $Credential
            }
            
            $uninstallKeys = Invoke-Command @regParams -ScriptBlock {
                $software = @()
                $paths = @(
                    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
                )
                foreach ($path in $paths) {
                    $items = Get-ItemProperty $path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }
                    foreach ($item in $items) {
                        $name = $item.DisplayName
                        $version = $item.DisplayVersion
                        if ($name -and $version) {
                            $software += "$name $version"
                        }
                        elseif ($name) {
                            $software += $name
                        }
                    }
                }
                return $software
            }
            
            if ($uninstallKeys) {
                $softwareReg = $uninstallKeys
            }
        }
        catch {
        }
        
        $allSoftware = ($software + $softwareReg) | Select-Object -Unique | Sort-Object
        
        return @{
            OsVersion = $osVersion
            Roles = $roles
            Software = $allSoftware
        }
    }
    catch {
        Write-Warning "Sanitized status message"
        return $null
    }
}

function Get-ServerInfoRemote {
    param(
        [string]$ServerName,
        [PSCredential]$Credential
    )
    
    try {
        $invokeParams = @{
            ComputerName = $ServerName
            ScriptBlock = {
                $result = @{}
                
                $os = Get-CimInstance -ClassName Win32_OperatingSystem
                $result.OsVersion = "$($os.Caption) $($os.Version)"
                
                $roles = @()
                try {
                    $features = Get-WindowsFeature | Where-Object { $_.InstallState -eq "Installed" }
                    foreach ($feature in $features) {
                        $roles += $feature.Name
                    }
                }
                catch {
                    try {
                        $dismOutput = DISM /online /Get-Features /Format:List | Where-Object { $_ -like "*State : Enabled*" }
                        foreach ($line in $dismOutput) {
                            if ($line -match "Feature Name : (.+)") {
                                $roles += $matches[1]
                            }
                        }
                    }
                    catch {
                    }
                }
                $result.Roles = $roles
                
                $software = @()
                $paths = @(
                    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
                )
                foreach ($path in $paths) {
                    $items = Get-ItemProperty $path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }
                    foreach ($item in $items) {
                        $name = $item.DisplayName
                        $version = $item.DisplayVersion
                        if ($name) {
                            if ($version) {
                                $software += "$name $version"
                            }
                            else {
                                $software += $name
                            }
                        }
                    }
                }
                
                $importantSoftware = $software | Where-Object {
                    $_ -like "*SQL Server*" -or
                    $_ -like "*1C*" -or
                    $_ -like "*Apache*" -or
                    $_ -like "*IIS*" -or
                    $_ -like "*Zabbix*" -or
                    $_ -like "*Wazuh*" -or
                    $_ -like "*Backup*"
                }
                
                $result.Software = ($importantSoftware + $software | Select-Object -First 50) | Sort-Object -Unique
                
                return $result
            }
            ErrorAction = "Stop"
        }
        
        if ($Credential) {
            $invokeParams.Credential = $Credential
        }
        
        return Invoke-Command @invokeParams
    }
    catch {
        Write-Warning "Sanitized status message"
        return $null
    }
}

function Write-ServerSoftwareToDatabase {
    param(
        [array]$Results,
        [string]$ConnString
    )
    
    if ($Results.Count -eq 0) {
        Write-Warning "Sanitized status message"
        return
    }
    
    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection($ConnString)
        $connection.Open()
        
        foreach ($result in $Results) {
            if ($result.ServerId -eq 0) {
                try {
                    $findQuery = "SELECT ServerId FROM dim.Server WHERE ServerName = @ServerName"
                    $findCmd = New-Object System.Data.SqlClient.SqlCommand($findQuery, $connection)
                    $findCmd.Parameters.AddWithValue("@ServerName", $result.ServerName) | Out-Null
                    $serverIdObj = $findCmd.ExecuteScalar()
                    
                    if ($serverIdObj) {
                        $result.ServerId = [int]$serverIdObj
                    }
                    else {
                        $insertServerQuery = @"
                            INSERT INTO dim.Server (ServerName, IsActive, CreatedAt)
                            OUTPUT INSERTED.ServerId
                            VALUES (@ServerName, 1, GETUTCDATE())
"@
                        $insertCmd = New-Object System.Data.SqlClient.SqlCommand($insertServerQuery, $connection)
                        $insertCmd.Parameters.AddWithValue("@ServerName", $result.ServerName) | Out-Null
                        $result.ServerId = [int]$insertCmd.ExecuteScalar()
                        Write-Host "Sanitized status message" -ForegroundColor Green
                    }
                }
                catch {
                    Write-Warning "Sanitized status message"
                    continue
                }
            }
            
            $rolesJson = if ($result.Roles) {
                ($result.Roles | ConvertTo-Json -Compress)
            } else {
                "[]"
            }
            
            $softwareJson = if ($result.Software) {
                ($result.Software | ConvertTo-Json -Compress)
            } else {
                "[]"
            }
            
            $insertQuery = @"
                INSERT INTO fact.SoftwareAudit (CaptureTime, ServerId, OsVersion, RolesJson, SoftwareJson)
                VALUES (@CaptureTime, @ServerId, @OsVersion, @RolesJson, @SoftwareJson)
"@
            
            $insertCmd = New-Object System.Data.SqlClient.SqlCommand($insertQuery, $connection)
            $insertCmd.Parameters.AddWithValue("@CaptureTime", $result.CaptureTime) | Out-Null
            $insertCmd.Parameters.AddWithValue("@ServerId", $result.ServerId) | Out-Null
            $osVersionValue = if ($result.OsVersion) { [object]$result.OsVersion } else { [DBNull]::Value }
            $insertCmd.Parameters.AddWithValue("@OsVersion", $osVersionValue) | Out-Null
            $insertCmd.Parameters.AddWithValue("@RolesJson", $rolesJson) | Out-Null
            $insertCmd.Parameters.AddWithValue("@SoftwareJson", $softwareJson) | Out-Null
            
            $insertCmd.ExecuteNonQuery() | Out-Null
        }
        
        $connection.Close()
        Write-Host "Sanitized status message" -ForegroundColor Green
    }
    catch {
        Write-Error "Sanitized status message"
    }
}

Write-Host "Sanitized status message" -ForegroundColor Cyan
Write-Host ""

if ($UseActiveDirectory) {
    Write-Host "Sanitized status message" -ForegroundColor Yellow
    $servers = Get-ServersFromAD -Domain $DomainName
}
else {
    Write-Host "Sanitized status message" -ForegroundColor Yellow
    $servers = Get-ServersFromDatabase -ConnString $ConnectionString
}

if ($servers.Count -eq 0) {
    Write-Warning "Sanitized status message"
    exit 1
}

Write-Host "Sanitized status message" -ForegroundColor Green
Write-Host ""

$allResults = @()
$successCount = 0
$failCount = 0

foreach ($server in $servers) {
    $serverName = $server.ServerName
    $serverId = $server.ServerId
    
    Write-Host "Sanitized status message" -ForegroundColor Cyan
    
    $info = $null
    if ($UseWMI) {
        $info = Get-ServerInfoWMI -ServerName $serverName -Credential $Credential
    }
    else {
        $info = Get-ServerInfoRemote -ServerName $serverName -Credential $Credential
    }
    
    if ($info) {
        $allResults += @{
            ServerId = $serverId
            ServerName = $serverName
            CaptureTime = Get-Date
            OsVersion = $info.OsVersion
            Roles = $info.Roles
            Software = $info.Software
        }
        $successCount++
        Write-Host "Sanitized status message" -ForegroundColor Green
    }
    else {
        $failCount++
        Write-Host "Sanitized status message" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Sanitized status message" -ForegroundColor Cyan
Write-Host "Sanitized status message" -ForegroundColor Green
Write-Host "Sanitized status message" -ForegroundColor Red
Write-Host ""

if ($allResults.Count -gt 0) {
    Write-Host "Sanitized status message" -ForegroundColor Yellow
    Write-ServerSoftwareToDatabase -Results $allResults -ConnString $ConnectionString
}

Write-Host ""
Write-Host "Sanitized status message" -ForegroundColor Green

