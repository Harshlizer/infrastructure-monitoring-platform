# Sanitized sample from an internal infrastructure monitoring project.
# Secrets, internal identifiers, and localized text have been removed or generalized.

param(
    [string]$ConnectionString = "Server=<SQL_SERVER>;Database=<MONITORING_DATABASE>;User ID=<SQL_USERNAME>;Password=<SQL_PASSWORD>;TrustServerCertificate=True;",
    [switch]$UseActiveDirectory = $false,
    [string]$DomainName = $null,
    [PSCredential]$Credential = $null,
    [switch]$UseWMI = $false,
    [switch]$SkipWinRMErrors = $false
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

function Get-FirewallStatusWMI {
    param(
        [string]$ServerName,
        [int]$ServerId,
        [PSCredential]$Credential
    )
    
    $results = @()
    $captureTime = Get-Date
    
    try {
        $wmiParams = @{
            Namespace = "root\StandardCimv2"
            Class = "MSFT_NetFirewallProfile"
            ComputerName = $ServerName
            ErrorAction = "Stop"
        }
        
        if ($Credential) {
            $wmiParams.Credential = $Credential
        }
        
        $profiles = Get-CimInstance @wmiParams
        
        foreach ($profile in $profiles) {
            $profileName = $profile.InstanceID -replace ".*ProfileType=(\w+).*", '$1'
            $state = if ($profile.Enabled) { "Enabled" } else { "Disabled" }
            
            $profileDisplayName = switch ($profileName) {
                "Domain" { "Domain" }
                "Private" { "Private" }
                "Public" { "Public" }
                default { $profileName }
            }
            
            $results += @{
                ServerId = $ServerId
                ServerName = $ServerName
                CaptureTime = $captureTime
                Profile = $profileDisplayName
                State = $state
            }
        }
        
        return $results
    }
    catch {
        Write-Warning "Sanitized status message"
        return $null
    }
}

function Get-FirewallStatusRemote {
    param(
        [string]$ServerName,
        [int]$ServerId,
        [PSCredential]$Credential = $null,
        [bool]$UseWMI = $false,
        [bool]$SkipWinRMErrors = $false
    )
    
    $results = @()
    $captureTime = Get-Date
    
    try {
        $ping = Test-Connection -ComputerName $ServerName -Count 1 -Quiet -ErrorAction SilentlyContinue
        
        if (-not $ping) {
            Write-Warning "Sanitized status message"
            return $null
        }
        
        if ($UseWMI) {
            $wmiResults = Get-FirewallStatusWMI -ServerName $ServerName -ServerId $ServerId -Credential $Credential
            if ($wmiResults) {
                return $wmiResults
            }
        }
        
        $invokeParams = @{
            ComputerName = $ServerName
            ScriptBlock = {
                $result = @{
                    FirewallProfiles = @()
                    Services = @{}
                }
                
                # Firewall profiles
                $domainProfile = Get-NetFirewallProfile -Profile Domain -ErrorAction SilentlyContinue
                $privateProfile = Get-NetFirewallProfile -Profile Private -ErrorAction SilentlyContinue
                $publicProfile = Get-NetFirewallProfile -Profile Public -ErrorAction SilentlyContinue
                
                if ($domainProfile) {
                    $result.FirewallProfiles += @{
                        Profile = "Domain"
                        State = if ($domainProfile.Enabled) { "Enabled" } else { "Disabled" }
                    }
                }
                if ($privateProfile) {
                    $result.FirewallProfiles += @{
                        Profile = "Private"
                        State = if ($privateProfile.Enabled) { "Enabled" } else { "Disabled" }
                    }
                }
                if ($publicProfile) {
                    $result.FirewallProfiles += @{
                        Profile = "Public"
                        State = if ($publicProfile.Enabled) { "Enabled" } else { "Disabled" }
                    }
                }
                
                # Check services: Zabbix, Wazuh, Qualys
                $serviceNames = @{
                    "Zabbix" = @("Zabbix Agent", "zabbix_agentd", "Zabbix")
                    "Wazuh" = @("Wazuh", "wazuh-agent", "ossec-agent")
                    "Qualys" = @("Qualys", "QualysAgent", "Qualys Cloud Agent")
                }
                
                foreach ($serviceKey in $serviceNames.Keys) {
                    $found = $false
                    foreach ($serviceName in $serviceNames[$serviceKey]) {
                        try {
                            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                            if ($service) {
                                $result.Services[$serviceKey] = if ($service.Status -eq "Running") { "Running" } else { "Stopped" }
                                $found = $true
                                break
                            }
                        }
                        catch {
                            # Service not found, continue
                        }
                    }
                    if (-not $found) {
                        $result.Services[$serviceKey] = "NotInstalled"
                    }
                }
                
                return $result
            }
            ErrorAction = "Stop"
        }
        
        if ($Credential) {
            $invokeParams.Credential = $Credential
        }
        
        $remoteResult = Invoke-Command @invokeParams
        
        # Process firewall profiles
        foreach ($profile in $remoteResult.FirewallProfiles) {
            $results += @{
                ServerId = $ServerId
                ServerName = $ServerName
                CaptureTime = $captureTime
                Profile = $profile.Profile
                State = $profile.State
            }
        }
        
        # Process services (Zabbix, Wazuh, Qualys)
        if ($remoteResult.Services) {
            foreach ($serviceKey in $remoteResult.Services.Keys) {
                $serviceStatus = $remoteResult.Services[$serviceKey]
                $results += @{
                    ServerId = $ServerId
                    ServerName = $ServerName
                    CaptureTime = $captureTime
                    Profile = $serviceKey  # Using Profile field for service name
                    State = $serviceStatus
                }
            }
        }
        
        return $results
    }
    catch {
        $errorMsg = $_.Exception.Message
        
        if ($SkipWinRMErrors -and ($errorMsg -like "*Access is denied*" -or $errorMsg -like "*Access denied*")) {
            Write-Host "Sanitized status message" -ForegroundColor Yellow
            $wmiResults = Get-FirewallStatusWMI -ServerName $ServerName -ServerId $ServerId -Credential $Credential
            if ($wmiResults) {
                Write-Host "Sanitized status message" -ForegroundColor Green
                return $wmiResults
            }
        }
        
        Write-Warning "Sanitized status message"
        return $null
    }
}

function Write-FirewallStatusToDatabase {
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
            
            $insertQuery = @"
                INSERT INTO fact.FirewallStatus (CaptureTime, ServerId, Profile, State, Source)
                VALUES (@CaptureTime, @ServerId, @Profile, @State, @Source)
"@
            
            $insertCmd = New-Object System.Data.SqlClient.SqlCommand($insertQuery, $connection)
            $insertCmd.Parameters.AddWithValue("@CaptureTime", $result.CaptureTime) | Out-Null
            $insertCmd.Parameters.AddWithValue("@ServerId", $result.ServerId) | Out-Null
            $insertCmd.Parameters.AddWithValue("@Profile", $result.Profile) | Out-Null
            $insertCmd.Parameters.AddWithValue("@State", $result.State) | Out-Null
            $insertCmd.Parameters.AddWithValue("@Source", "PowerShell Script") | Out-Null
            
            $insertCmd.ExecuteNonQuery() | Out-Null
        }
        
        $connection.Close()
        Write-Host "Sanitized status message" -ForegroundColor Green
    }
    catch {
        $errorMessage = $_.Exception.Message
        if ($errorMessage -like "*permission*denied*" -or $errorMessage -like "*INSERT permission*") {
            Write-Error "Sanitized status message"
            Write-Host ""
            Write-Host "Sanitized status message" -ForegroundColor Yellow
            Write-Host "Sanitized status message" -ForegroundColor Yellow
            Write-Host ""
        }
        else {
            Write-Error "Sanitized status message"
        }
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
    
    $results = Get-FirewallStatusRemote -ServerName $serverName -ServerId $serverId -Credential $Credential -UseWMI $UseWMI -SkipWinRMErrors $SkipWinRMErrors
    
    if ($results) {
        $allResults += $results
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
Write-Host "Sanitized status message" -ForegroundColor Yellow
Write-Host ""

if ($allResults.Count -gt 0) {
    Write-Host "Sanitized status message" -ForegroundColor Yellow
    Write-FirewallStatusToDatabase -Results $allResults -ConnString $ConnectionString
}

Write-Host ""
Write-Host "Sanitized status message" -ForegroundColor Green

