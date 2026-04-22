# Sanitized sample from an internal infrastructure monitoring project.
# Secrets, internal identifiers, and localized text have been removed or generalized.

param(
    [string]$ConnectionString = "Server=<SQL_SERVER>;Database=<MONITORING_DATABASE>;User ID=<SQL_USERNAME>;Password=<SQL_PASSWORD>;TrustServerCertificate=True;"
)

$ErrorActionPreference = "Stop"

Write-Host "Sanitized status message" -ForegroundColor Cyan

$TenantId     = "<TENANT_ID>"
$ClientId     = "<CLIENT_ID>"
$ClientSecret = "<CLIENT_SECRET>"

$licensePrices = @{
    "O365_BUSINESS_ESSENTIALS" = 4.75
    "O365_BUSINESS_PREMIUM" = 10.03
    "SPB" = 10.03
    "O365_STANDARD" = 10.03
    "O365_BUSINESS" = 10.05
    "OFFICESUBSCRIPTION" = 10.05
    "TEAMS_ESSENTIALS" = 3.80
    "TEAMS_PREMIUM" = 8.63
    "ENTERPRISEPACK" = 25.80
    "STANDARDPACK" = 9.58
    "POWER_BI_PRO" = 8.05
    "POWER_BI_PREMIUM_PER_USER" = 19.23
    "SPE_F1" = 2.34
    "MICROSOFT_365_F1" = 2.34
    "M365_F1" = 2.34
    "OFFICE_365_F1" = 2.34
    "O365_F1" = 2.34
    "F1" = 2.34
    "F1_FIRSTLINE" = 2.34
    "M365_F1_COMM" = 2.34
    
    "ENTERPRISEPREMIUM" = 38.00
    "M365_E3" = 33.00
    "M365_E5" = 57.00
    "M365_E5_SECURITY" = 11.20
    "M365_E5_COMPLIANCE" = 10.60
    "IDENTITY_GOVERNANCE" = 5.60
    "EMS" = 6.70
    "EMSPREMIUM" = 10.20
    "AAD_PREMIUM" = 3.40
    "AAD_PREMIUM_P2" = 5.60
    "MCOPSTNC" = 6.80
    "MCOPSTN2" = 17.40
    "POWERAPPS_PER_APP" = 4.20
    "POWERAPPS_PER_USER" = 15.10
    "PROJECT_PLAN_1" = 7.50
    "PROJECT_PLAN_3" = 25.00
    "VISIO_PLAN1" = 4.30
    "VISIO_PLAN2" = 11.60
    "DEFENDER_ENDPOINT_P1" = 3.00
    "DEFENDER_ENDPOINT_P2" = 5.20
    "DEFENDER_IDENTITY" = 4.50
    "DEFENDER_OFFICE365_P1" = 1.60
    "DEFENDER_OFFICE365_P2" = 3.20
    "INTUNE_A" = 5.70
    "INTUNE_SUITE" = 8.50
    
    # Microsoft 365 Copilot
    "M365_COPILOT" = 27.50
    "COPILOT_STANDARD" = 27.50
    "Microsoft_365_Copilot" = 27.50
    
    "THREAT_INTELLIGENCE" = 0.00  # TODO:  
    "EXCHANGESTANDARD" = 0.00  # TODO:  
    "Microsoft_Teams_Premium" = 8.63  #  TEAMS_PREMIUM
    "Microsoft_Teams_Exploratory_Dept" = 0.00  # TODO:  
    "POWER_BI_STANDARD" = 4.20  #   Check-M365InactiveUsers.ps1
    "PBI_PREMIUM_PER_USER" = 19.23  #  POWER_BI_PREMIUM_PER_USER
    "TEAMS_ESSENTIALS_AAD" = 3.80  #  TEAMS_ESSENTIALS
    "PROJECTPROFESSIONAL" = 0.00  # TODO:  
    "POWERAUTOMATE_ATTENDED_RPA" = 0.00  # TODO:  
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

Write-Host "Sanitized status message" -ForegroundColor Yellow
try {
    $users = Get-MgUser -All -Property Id, DisplayName, Department, AssignedLicenses
    Write-Host "Sanitized status message" -ForegroundColor Green
}
catch {
    Write-Error "Sanitized status message"
    Disconnect-MgGraph | Out-Null
    exit 1
}

$departmentLicenses = @{}

Write-Host "Sanitized status message" -ForegroundColor Yellow
$count = 0
$total = $users.Count

foreach ($user in $users) {
    $count++
    if ($count % 50 -eq 0) {
        Write-Progress -Activity "Sanitized status message" -Status "Sanitized status message" -PercentComplete (($count / $total)*100)
    }
    
    if ($user.Department -and $user.AssignedLicenses.Count -gt 0) {
        $department = $user.Department
        
        if (-not $departmentLicenses.ContainsKey($department)) {
            $departmentLicenses[$department] = @{
                TotalCost = 0
                LicenseCounts = @{}
            }
        }
        
        try {
            $licenses = Get-MgUserLicenseDetail -UserId $user.Id
            foreach ($license in $licenses) {
                $skuName = $license.SkuPartNumber
                if ($licensePrices.ContainsKey($skuName)) {
                    $departmentLicenses[$department].TotalCost += $licensePrices[$skuName]
                    
                    if (-not $departmentLicenses[$department].LicenseCounts.ContainsKey($skuName)) {
                        $departmentLicenses[$department].LicenseCounts[$skuName] = 0
                    }
                    $departmentLicenses[$department].LicenseCounts[$skuName]++
                }
            }
        }
        catch {
            Write-Warning "Sanitized status message"
        }
    }
}

Write-Progress -Activity "Sanitized status message" -Completed
Write-Host "Sanitized status message" -ForegroundColor Green

try {
    $connection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
    $connection.Open()
    Write-Host "Sanitized status message" -ForegroundColor Green
    
    $snapshotDate = Get-Date -Format "yyyy-MM-dd"
    
    $deleteQuery = @"
        DELETE FROM fact.M365LicenseCostByDepartment 
        WHERE SnapshotDate = @SnapshotDate
"@
    $deleteCmd = New-Object System.Data.SqlClient.SqlCommand($deleteQuery, $connection)
    $deleteCmd.Parameters.AddWithValue("@SnapshotDate", $snapshotDate) | Out-Null
    $deletedRows = $deleteCmd.ExecuteNonQuery()
    Write-Host "Sanitized status message" -ForegroundColor Yellow
    
    $insertQuery = @"
        INSERT INTO fact.M365LicenseCostByDepartment (
            SnapshotDate,
            Department,
            TotalCost,
            ENTERPRISEPACK,
            F1,
            F1_FIRSTLINE,
            M365_F1,
            M365_F1_COMM,
            MICROSOFT_365_F1,
            O365_BUSINESS,
            O365_BUSINESS_ESSENTIALS,
            O365_BUSINESS_PREMIUM,
            O365_F1,
            O365_STANDARD,
            OFFICE_365_F1,
            OFFICESUBSCRIPTION,
            POWER_BI_PREMIUM_PER_USER,
            POWER_BI_PRO,
            SPB,
            SPE_F1,
            STANDARDPACK,
            TEAMS_ESSENTIALS,
            TEAMS_PREMIUM,
            ENTERPRISEPREMIUM,
            M365_E3,
            M365_E5,
            M365_E5_SECURITY,
            M365_E5_COMPLIANCE,
            IDENTITY_GOVERNANCE,
            EMS,
            EMSPREMIUM,
            AAD_PREMIUM,
            AAD_PREMIUM_P2,
            MCOPSTNC,
            MCOPSTN2,
            POWERAPPS_PER_APP,
            POWERAPPS_PER_USER,
            PROJECT_PLAN_1,
            PROJECT_PLAN_3,
            VISIO_PLAN1,
            VISIO_PLAN2,
            DEFENDER_ENDPOINT_P1,
            DEFENDER_ENDPOINT_P2,
            DEFENDER_IDENTITY,
            DEFENDER_OFFICE365_P1,
            DEFENDER_OFFICE365_P2,
            INTUNE_A,
            INTUNE_SUITE,
            M365_COPILOT,
            COPILOT_STANDARD,
            THREAT_INTELLIGENCE,
            EXCHANGESTANDARD,
            Microsoft_Teams_Premium,
            Microsoft_Teams_Exploratory_Dept,
            POWER_BI_STANDARD,
            PBI_PREMIUM_PER_USER,
            TEAMS_ESSENTIALS_AAD,
            PROJECTPROFESSIONAL,
            POWERAUTOMATE_ATTENDED_RPA,
            Microsoft_365_Copilot,
            Source
        )
        VALUES (
            @SnapshotDate,
            @Department,
            @TotalCost,
            @ENTERPRISEPACK,
            @F1,
            @F1_FIRSTLINE,
            @M365_F1,
            @M365_F1_COMM,
            @MICROSOFT_365_F1,
            @O365_BUSINESS,
            @O365_BUSINESS_ESSENTIALS,
            @O365_BUSINESS_PREMIUM,
            @O365_F1,
            @O365_STANDARD,
            @OFFICE_365_F1,
            @OFFICESUBSCRIPTION,
            @POWER_BI_PREMIUM_PER_USER,
            @POWER_BI_PRO,
            @SPB,
            @SPE_F1,
            @STANDARDPACK,
            @TEAMS_ESSENTIALS,
            @TEAMS_PREMIUM,
            @ENTERPRISEPREMIUM,
            @M365_E3,
            @M365_E5,
            @M365_E5_SECURITY,
            @M365_E5_COMPLIANCE,
            @IDENTITY_GOVERNANCE,
            @EMS,
            @EMSPREMIUM,
            @AAD_PREMIUM,
            @AAD_PREMIUM_P2,
            @MCOPSTNC,
            @MCOPSTN2,
            @POWERAPPS_PER_APP,
            @POWERAPPS_PER_USER,
            @PROJECT_PLAN_1,
            @PROJECT_PLAN_3,
            @VISIO_PLAN1,
            @VISIO_PLAN2,
            @DEFENDER_ENDPOINT_P1,
            @DEFENDER_ENDPOINT_P2,
            @DEFENDER_IDENTITY,
            @DEFENDER_OFFICE365_P1,
            @DEFENDER_OFFICE365_P2,
            @INTUNE_A,
            @INTUNE_SUITE,
            @M365_COPILOT,
            @COPILOT_STANDARD,
            @THREAT_INTELLIGENCE,
            @EXCHANGESTANDARD,
            @Microsoft_Teams_Premium,
            @Microsoft_Teams_Exploratory_Dept,
            @POWER_BI_STANDARD,
            @PBI_PREMIUM_PER_USER,
            @TEAMS_ESSENTIALS_AAD,
            @PROJECTPROFESSIONAL,
            @POWERAUTOMATE_ATTENDED_RPA,
            @Microsoft_365_Copilot,
            @Source
        )
"@
    
    $insertedCount = 0
    
    $allLicenseTypes = @(
        "ENTERPRISEPACK", "F1", "F1_FIRSTLINE", "M365_F1", "M365_F1_COMM", "MICROSOFT_365_F1",
        "O365_BUSINESS", "O365_BUSINESS_ESSENTIALS", "O365_BUSINESS_PREMIUM", "O365_F1", "O365_STANDARD",
        "OFFICE_365_F1", "OFFICESUBSCRIPTION", "POWER_BI_PREMIUM_PER_USER", "POWER_BI_PRO",
        "SPB", "SPE_F1", "STANDARDPACK", "TEAMS_ESSENTIALS", "TEAMS_PREMIUM",
        "ENTERPRISEPREMIUM", "M365_E3", "M365_E5", "M365_E5_SECURITY", "M365_E5_COMPLIANCE",
        "IDENTITY_GOVERNANCE", "EMS", "EMSPREMIUM", "AAD_PREMIUM", "AAD_PREMIUM_P2",
        "MCOPSTNC", "MCOPSTN2", "POWERAPPS_PER_APP", "POWERAPPS_PER_USER",
        "PROJECT_PLAN_1", "PROJECT_PLAN_3", "VISIO_PLAN1", "VISIO_PLAN2",
        "DEFENDER_ENDPOINT_P1", "DEFENDER_ENDPOINT_P2", "DEFENDER_IDENTITY",
        "DEFENDER_OFFICE365_P1", "DEFENDER_OFFICE365_P2", "INTUNE_A", "INTUNE_SUITE",
        "M365_COPILOT", "COPILOT_STANDARD", "THREAT_INTELLIGENCE", "EXCHANGESTANDARD",
        "Microsoft_Teams_Premium", "Microsoft_Teams_Exploratory_Dept", "POWER_BI_STANDARD",
        "PBI_PREMIUM_PER_USER", "TEAMS_ESSENTIALS_AAD", "PROJECTPROFESSIONAL",
        "POWERAUTOMATE_ATTENDED_RPA", "Microsoft_365_Copilot"
    )
    
    foreach ($department in $departmentLicenses.Keys | Sort-Object) {
        try {
            $insertCmd = New-Object System.Data.SqlClient.SqlCommand($insertQuery, $connection)
            
            $insertCmd.Parameters.AddWithValue("@SnapshotDate", $snapshotDate) | Out-Null
            $insertCmd.Parameters.AddWithValue("@Department", $department) | Out-Null
            $insertCmd.Parameters.AddWithValue("@TotalCost", [math]::Round($departmentLicenses[$department].TotalCost, 2)) | Out-Null
            
            foreach ($licenseType in $allLicenseTypes) {
                $count = 0
                if ($departmentLicenses[$department].LicenseCounts.ContainsKey($licenseType)) {
                    $count = $departmentLicenses[$department].LicenseCounts[$licenseType]
                }
                $insertCmd.Parameters.AddWithValue("@$licenseType", $count) | Out-Null
            }
            
            $insertCmd.Parameters.AddWithValue("@Source", "Check-M365LicenseCostByDepartment") | Out-Null
            
            $insertCmd.ExecuteNonQuery() | Out-Null
            $insertedCount++
        }
        catch {
            Write-Warning "Sanitized status message"
        }
    }
    
    $connection.Close()
    Write-Host "Sanitized status message" -ForegroundColor Green
}
catch {
    Write-Error "Sanitized status message"
    Disconnect-MgGraph | Out-Null
    exit 1
}

Disconnect-MgGraph | Out-Null

Write-Host "Sanitized status message" -ForegroundColor Green

