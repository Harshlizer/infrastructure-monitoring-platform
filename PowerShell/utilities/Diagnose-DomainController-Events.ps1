# Sanitized sample from an internal infrastructure monitoring project.
# Secrets, internal identifiers, and localized text have been removed or generalized.

# Diagnostic script to check AD events on <DOMAIN_CONTROLLER>
# This script helps diagnose why events are not being found

param(
    [string]$ServerName = "<DOMAIN_CONTROLLER>",
    [int]$HoursBack = 24
)

$startTime = (Get-Date).AddHours(-$HoursBack)

Write-Host "=== Diagnostic: Checking AD events on $ServerName ===" -ForegroundColor Cyan
Write-Host "Time range: from $($startTime.ToString('yyyy-MM-dd HH:mm:ss')) to $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host ""

# Test connectivity
Write-Host "1. Testing connectivity..." -ForegroundColor Cyan
$ping = Test-Connection -ComputerName $ServerName -Count 1 -Quiet -ErrorAction SilentlyContinue
if ($ping) {
    Write-Host "   ✓ Server is reachable" -ForegroundColor Green
} else {
    Write-Host "   ✗ Server is NOT reachable (ping failed)" -ForegroundColor Red
    exit 1
}

# Check if we can access Security log
Write-Host ""
Write-Host "2. Checking Security log accessibility..." -ForegroundColor Cyan
try {
    $testEvents = Invoke-Command -ComputerName $ServerName -ScriptBlock {
        param($StartTime)
        Get-WinEvent -FilterHashtable @{
            LogName = 'Security'
            StartTime = $StartTime
        } -MaxEvents 10 -ErrorAction Stop
    } -ArgumentList $startTime
    
    if ($testEvents) {
        Write-Host "   ✓ Security log is accessible" -ForegroundColor Green
        Write-Host "   Found $($testEvents.Count) recent event(s)" -ForegroundColor Gray
        
        # Show Event IDs
        $eventIds = $testEvents | Select-Object -ExpandProperty Id -Unique | Sort-Object
        Write-Host "   Event IDs found: $($eventIds -join ', ')" -ForegroundColor Gray
    } else {
        Write-Host "   ⚠ Security log is accessible but no events found in the time range" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "   ✗ Error accessing Security log: $($_.Exception.Message)" -ForegroundColor Red
}

# Check specific AD event IDs
Write-Host ""
Write-Host "3. Checking for specific AD event IDs..." -ForegroundColor Cyan
$adEventIds = @(
    @{Id = 4720; Name = "User Created"},
    @{Id = 4726; Name = "User Deleted"},
    @{Id = 4727; Name = "Group Created"},
    @{Id = 4729; Name = "Group Deleted"},
    @{Id = 4728; Name = "Member Added to Global Group"},
    @{Id = 4732; Name = "Member Removed from Global Group"},
    @{Id = 4756; Name = "Member Added to Universal Group"},
    @{Id = 4757; Name = "Member Removed from Universal Group"}
)

foreach ($eventInfo in $adEventIds) {
    try {
        $events = Invoke-Command -ComputerName $ServerName -ScriptBlock {
            param($EventId, $StartTime)
            Get-WinEvent -FilterHashtable @{
                LogName = 'Security'
                Id = $EventId
                StartTime = $StartTime
            } -MaxEvents 5 -ErrorAction SilentlyContinue
        } -ArgumentList $eventInfo.Id, $startTime
        
        if ($events) {
            Write-Host "   ✓ Event ID $($eventInfo.Id) ($($eventInfo.Name)): Found $($events.Count) event(s)" -ForegroundColor Green
            # Show first event details
            $firstEvent = $events[0]
            Write-Host "      First event time: $($firstEvent.TimeCreated)" -ForegroundColor Gray
            Write-Host "      First event message preview: $($firstEvent.Message.Substring(0, [Math]::Min(100, $firstEvent.Message.Length)))..." -ForegroundColor Gray
        } else {
            Write-Host "   - Event ID $($eventInfo.Id) ($($eventInfo.Name)): No events found" -ForegroundColor Gray
        }
    }
    catch {
        if ($_.Exception.Message -like "*No events*") {
            Write-Host "   - Event ID $($eventInfo.Id) ($($eventInfo.Name)): No events found" -ForegroundColor Gray
        } else {
            Write-Host "   ✗ Error checking Event ID $($eventInfo.Id): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# Check Directory Service log
Write-Host ""
Write-Host "4. Checking Directory Service log..." -ForegroundColor Cyan
try {
    $dsEvents = Invoke-Command -ComputerName $ServerName -ScriptBlock {
        param($StartTime)
        Get-WinEvent -FilterHashtable @{
            LogName = 'Directory Service'
            StartTime = $StartTime
        } -MaxEvents 10 -ErrorAction SilentlyContinue
    } -ArgumentList $startTime
    
    if ($dsEvents) {
        Write-Host "   ✓ Directory Service log is accessible" -ForegroundColor Green
        Write-Host "   Found $($dsEvents.Count) recent event(s)" -ForegroundColor Gray
        
        $dsEventIds = $dsEvents | Select-Object -ExpandProperty Id -Unique | Sort-Object
        Write-Host "   Event IDs found: $($dsEventIds -join ', ')" -ForegroundColor Gray
    } else {
        Write-Host "   - Directory Service log: No events found in the time range" -ForegroundColor Gray
    }
}
catch {
    if ($_.Exception.Message -like "*No events*" -or $_.Exception.Message -like "*not found*") {
        Write-Host "   - Directory Service log: No events found or log doesn't exist" -ForegroundColor Gray
    } else {
        Write-Host "   ✗ Error accessing Directory Service log: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Check audit policy
Write-Host ""
Write-Host "5. Checking Audit Policy (requires admin rights)..." -ForegroundColor Cyan
try {
    $auditPolicy = Invoke-Command -ComputerName $ServerName -ScriptBlock {
        auditpol /get /category:"Account Management" 2>&1
    } -ErrorAction SilentlyContinue
    
    if ($auditPolicy) {
        Write-Host "   Audit Policy for Account Management:" -ForegroundColor Gray
        $auditPolicy | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
    }
}
catch {
    Write-Host "   ⚠ Could not check audit policy (may require admin rights)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Diagnostic Complete ===" -ForegroundColor Cyan

