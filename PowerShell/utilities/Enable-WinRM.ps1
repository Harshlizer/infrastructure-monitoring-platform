# Sanitized sample from an internal infrastructure monitoring project.
# Secrets, internal identifiers, and localized text have been removed or generalized.

param(
    [string[]]$ComputerNames,
    [PSCredential]$Credential,
    [switch]$TrustAllHosts = $false
)

if (-not $ComputerNames) {
    Write-Host "Sanitized status message" -ForegroundColor Yellow
    $input = Read-Host
    if ($input) {
        $ComputerNames = $input -split ',' | ForEach-Object { $_.Trim() }
    }
    else {
        Write-Host "Sanitized status message" -ForegroundColor Yellow
        if (Test-Path "servers.txt") {
            $ComputerNames = Get-Content "servers.txt" | Where-Object { $_.Trim() -ne "" }
        }
        else {
            Write-Error "Sanitized status message"
            exit 1
        }
    }
}

Write-Host "Sanitized status message" -ForegroundColor Cyan
Write-Host "Sanitized status message" -ForegroundColor Yellow
Write-Host ""

if ($TrustAllHosts) {
    Write-Host "Sanitized status message" -ForegroundColor Yellow
    try {
        Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
        Write-Host "Sanitized status message" -ForegroundColor Green
    }
    catch {
        Write-Warning "Sanitized status message"
    }
    Write-Host ""
}

$successCount = 0
$failCount = 0

foreach ($computer in $ComputerNames) {
    $computer = $computer.Trim()
    if ([string]::IsNullOrWhiteSpace($computer)) { continue }
    
    Write-Host "Sanitized status message" -ForegroundColor Cyan
    
    try {
        $ping = Test-Connection -ComputerName $computer -Count 1 -Quiet -ErrorAction SilentlyContinue
        if (-not $ping) {
            Write-Warning "Sanitized status message"
            $failCount++
            continue
        }
        
        $invokeParams = @{
            ComputerName = $computer
            ScriptBlock = {
                Enable-PSRemoting -Force -SkipNetworkProfileCheck
                
                Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true -Force
                Set-Item WSMan:\localhost\Service\Auth\Negotiate -Value $true -Force
                
                Restart-Service WinRM -Force -ErrorAction SilentlyContinue
                
                return "OK"
            }
            ErrorAction = "Stop"
        }
        
        if ($Credential) {
            $invokeParams.Credential = $Credential
        }
        
        $result = Invoke-Command @invokeParams
        
        if ($result -eq "OK") {
            Write-Host "Sanitized status message" -ForegroundColor Green
            $successCount++
        }
        else {
            Write-Warning "Sanitized status message"
            $failCount++
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        if ($errorMsg -like "*Access is denied*" -or $errorMsg -like "*Access denied*") {
            Write-Warning "Sanitized status message"
            Write-Host "Sanitized status message" -ForegroundColor Yellow
            Write-Host "      Enable-PSRemoting -Force" -ForegroundColor Gray
            Write-Host "      Set-Item WSMan:\localhost\Service\Auth\Basic -Value `$true -Force" -ForegroundColor Gray
        }
        else {
            Write-Warning "Sanitized status message"
        }
        $failCount++
    }
}

Write-Host ""
Write-Host "Sanitized status message" -ForegroundColor Cyan
Write-Host "Sanitized status message" -ForegroundColor Green
Write-Host "Sanitized status message" -ForegroundColor Red
Write-Host ""

if ($failCount -gt 0) {
    Write-Host "Sanitized status message" -ForegroundColor Yellow
    Write-Host "  Enable-PSRemoting -Force" -ForegroundColor Gray
    Write-Host ""
}

