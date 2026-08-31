# Sanitized sample from an internal infrastructure monitoring project.
# Secrets, internal identifiers, and localized text have been removed or generalized.

param(
    [string]$ConnectionString = "Server=<SQL_SERVER>;Database=<MONITORING_DATABASE>;User ID=<SQL_USERNAME>;Password=<SQL_PASSWORD>;TrustServerCertificate=True;",
    [int]$InactiveDaysThreshold = 30
)

$ErrorActionPreference = "Stop"

Write-Host "Sanitized status message" -ForegroundColor Cyan

$TenantId     = "<TENANT_ID>"
$ClientId     = "<CLIENT_ID>"
$ClientSecret = "<CLIENT_SECRET>"

$today = Get-Date
$thresholdDate = $today.AddDays(-$InactiveDaysThreshold)
$excludeKeywords = @('exclude1','exclude2'
)

$productPrices = @{
    "O365_BUSINESS_ESSENTIALS" = 4.75
    "O365_BUSINESS_PREMIUM"    = 10.03
    "SPB"                      = 10.03
    "O365_STANDARD"            = 10.03
    "O365_BUSINESS"            = 10.05
    "OFFICESUBSCRIPTION"       = 10.05
    "TEAMS_ESSENTIALS"         = 3.80
    "TEAMS_ESSENTIALS_AAD"     = 3.80
    "TEAMS_PREMIUM"            = 8.63
    "ENTERPRISEPACK"           = 25.80
    "STANDARDPACK"             = 9.58
    "POWER_BI_PRO"             = 8.05
    "POWER_BI_PREMIUM_PER_USER"= 19.23
    "POWER_BI_STANDARD"        = 4.20
    "SPE_F1"                   = 2.34
    "MICROSOFT_365_F1"         = 2.34
    "M365_F1"                  = 2.34
    "OFFICE_365_F1"            = 2.34
    "O365_F1"                  = 2.34
    "F1"                       = 2.34
    "F1_FIRSTLINE"             = 2.34
    "M365_F1_COMM"             = 2.34
    "FLOW_FREE"                = 0
}

$modules = @("Microsoft.Graph")
foreach ($m in $modules) {
    if (!(Get-Module -ListAvailable -Name $m)) {
        Write-Host "Sanitized status message" -ForegroundColor Yellow
        Install-Module $m -Force -AllowClobber -Scope CurrentUser
    }
}

try {
    Write-Host "Sanitized status message" -ForegroundColor Yellow
    $secureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
    $credential   = New-Object System.Management.Automation.PSCredential ($ClientId, $secureSecret)
    Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $credential -NoWelcome
    Write-Host "Sanitized status message" -ForegroundColor Green
}
catch {
    Write-Error "Sanitized status message"
    exit 1
}

$exchangeOnlineAvailable = $false
if (Test-Path "<EXCHANGE_CREDENTIAL_PATH>") {
    try {
        $Cred = Import-Clixml "<EXCHANGE_CREDENTIAL_PATH>"
        Connect-ExchangeOnline -Credential $Cred -ShowBanner:$false -ErrorAction Stop
        $exchangeOnlineAvailable = $true
        Write-Host "Sanitized status message" -ForegroundColor Green
    }
    catch {
        Write-Host "Sanitized status message" -ForegroundColor Yellow
    }
}

Write-Host "Sanitized status message" -ForegroundColor Yellow
try {
    $allLicensedUsers = Get-MgUser -Filter "assignedLicenses/`$count ne 0 and accountEnabled eq true" `
        -ConsistencyLevel eventual -CountVariable total -All `
        -Property Id, DisplayName, UserPrincipalName, Mail, SignInActivity, UserType
    
    Write-Host "Sanitized status message" -ForegroundColor Green
}
catch {
    Write-Error "Sanitized status message"
    Disconnect-MgGraph | Out-Null
    exit 1
}

Write-Host "Sanitized status message" -ForegroundColor Yellow
$licensedUsers = @()
$excludedCount = 0

foreach ($user in $allLicensedUsers) {
    $exclude = $false
    
    if ($user.UserType -ne "Member") {
        $exclude = $true
    }
    
    if (-not $exclude) {
        $dn = $user.DisplayName.ToLower()
        $upn = $user.UserPrincipalName.ToLower()
        foreach ($kw in $excludeKeywords) {
            if ($dn -like "*$kw*" -or $upn -like "*$kw*") {
                $exclude = $true
                break
            }
        }
    }
    
    if ($exclude) {
        $excludedCount++
    } else {
        $licensedUsers += $user
    }
}

Write-Host "Sanitized status message" -ForegroundColor Green

try {
    $connection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
    $connection.Open()
    Write-Host "Sanitized status message" -ForegroundColor Green
    
    $snapshotDate = Get-Date -Format "yyyy-MM-dd"
    
    $deleteQuery = @"
        DELETE FROM fact.M365InactiveUser 
        WHERE SnapshotDate = @SnapshotDate
"@
    $deleteCmd = New-Object System.Data.SqlClient.SqlCommand($deleteQuery, $connection)
    $deleteCmd.Parameters.AddWithValue("@SnapshotDate", $snapshotDate) | Out-Null
    $deletedRows = $deleteCmd.ExecuteNonQuery()
    Write-Host "Sanitized status message" -ForegroundColor Yellow
    
    $insertQuery = @"
        INSERT INTO fact.M365InactiveUser (
            SnapshotDate,
            DisplayName,
            UserPrincipalName,
            Email,
            LastActivity,
            DaysSinceLastActivity,
            Licenses,
            MonthlyCost,
            Source
        )
        VALUES (
            @SnapshotDate,
            @DisplayName,
            @UserPrincipalName,
            @Email,
            @LastActivity,
            @DaysSinceLastActivity,
            @Licenses,
            @MonthlyCost,
            @Source
        )
"@
    
    $insertedCount = 0
    $count = 0
    $total = $licensedUsers.Count
    
    Write-Host "Sanitized status message" -ForegroundColor Yellow
    
    foreach ($user in $licensedUsers) {
        $count++
        if ($count % 10 -eq 0) {
            Write-Progress -Activity "Sanitized status message" -Status "Sanitized status message" -PercentComplete (($count / $total)*100)
        }
        
        $lastLogin = $null
        
        # Graph: SignInActivity
        if ($user.SignInActivity) {
            $li = $user.SignInActivity.LastSignInDateTime
            $ln = $user.SignInActivity.LastNonInteractiveSignInDateTime
            if ($li -and (!$lastLogin -or $li -gt $lastLogin)) { $lastLogin = $li }
            if ($ln -and (!$lastLogin -or $ln -gt $lastLogin)) { $lastLogin = $ln }
        }
        
        # Exchange Online fallback
        if (!$lastLogin -and $exchangeOnlineAvailable) {
            try {
                $stat = Get-MailboxStatistics -Identity $user.UserPrincipalName -ErrorAction Stop
                if ($stat.LastLogonTime) { $lastLogin = $stat.LastLogonTime }
            } catch {}
        }
        
        if (!$lastLogin -or $lastLogin -lt $thresholdDate) {
            try {
                $licenses = Get-MgUserLicenseDetail -UserId $user.Id -ErrorAction Stop
                $licenseDetails = @()
                $totalMonthlyCost = 0
                
                foreach ($lic in $licenses) {
                    $sku = $lic.SkuPartNumber
                    $price = if ($productPrices.ContainsKey($sku)) { $productPrices[$sku] } else { 0 }
                    
                    $licenseDetails += "$sku ($price €)"
                    $totalMonthlyCost += $price
                }
                
                if ($totalMonthlyCost -gt 0) {
                    $insertCmd = New-Object System.Data.SqlClient.SqlCommand($insertQuery, $connection)
                    
                    $insertCmd.Parameters.AddWithValue("@SnapshotDate", $snapshotDate) | Out-Null
                    $insertCmd.Parameters.AddWithValue("@DisplayName", $user.DisplayName) | Out-Null
                    $insertCmd.Parameters.AddWithValue("@UserPrincipalName", $user.UserPrincipalName) | Out-Null
                    
                    if ($user.Mail) {
                        $insertCmd.Parameters.AddWithValue("@Email", $user.Mail) | Out-Null
                    } else {
                        $insertCmd.Parameters.AddWithValue("@Email", [DBNull]::Value) | Out-Null
                    }
                    
                    if ($lastLogin) {
                        $insertCmd.Parameters.AddWithValue("@LastActivity", $lastLogin) | Out-Null
                    } else {
                        $insertCmd.Parameters.AddWithValue("@LastActivity", [DBNull]::Value) | Out-Null
                    }
                    
                    if ($lastLogin) {
                        $daysInactive = [math]::Round(($today - $lastLogin).TotalDays, 0)
                        $insertCmd.Parameters.AddWithValue("@DaysSinceLastActivity", [int]$daysInactive) | Out-Null
                    } else {
                        $insertCmd.Parameters.AddWithValue("@DaysSinceLastActivity", [DBNull]::Value) | Out-Null
                    }
                    
                    $insertCmd.Parameters.AddWithValue("@Licenses", ($licenseDetails -join ", ")) | Out-Null
                    $insertCmd.Parameters.AddWithValue("@MonthlyCost", [math]::Round($totalMonthlyCost, 2)) | Out-Null
                    $insertCmd.Parameters.AddWithValue("@Source", "PowerShell Script (Check-M365InactiveUsers)") | Out-Null
                    
                    $insertCmd.ExecuteNonQuery() | Out-Null
                    $insertedCount++
                }
            }
            catch {
                Write-Warning "Sanitized status message"
            }
        }
    }
    
    Write-Progress -Activity "Sanitized status message" -Completed
    
    $connection.Close()
    Write-Host "Sanitized status message" -ForegroundColor Green
}
catch {
    Write-Error "Sanitized status message"
    Disconnect-MgGraph | Out-Null
    if ($exchangeOnlineAvailable) { Disconnect-ExchangeOnline -Confirm:$false | Out-Null }
    exit 1
}

Disconnect-MgGraph | Out-Null
if ($exchangeOnlineAvailable) { Disconnect-ExchangeOnline -Confirm:$false | Out-Null }

Write-Host "Sanitized status message" -ForegroundColor Green

