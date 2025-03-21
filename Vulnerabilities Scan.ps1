# === Setup and Log ===
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$desktopPath = [Environment]::GetFolderPath("Desktop")
$logFile = Join-Path $desktopPath "VulnerabilityScan_$timestamp.txt"
function Log($msg) {
    $entry = "$(Get-Date -Format 'u') - $msg"
    Write-Host $entry
    Add-Content -Path $logFile -Value $entry
}

Log "==== Vulnerability Check Started ===="

# === 1. Check Windows Update / Missing Patches ===
Log "`nChecking for missing Windows updates..."
try {
    $updates = (New-Object -ComObject Microsoft.Update.Searcher).Search("IsInstalled=0").Updates
    if ($updates.Count -eq 0) {
        Log "✅ System is up to date."
    } else {
        Log "❗ Missing Updates Found:"
        $updates | ForEach-Object {
            Log " - $($_.Title)"
        }
    }
} catch {
    Log "⚠️ Could not query updates: $_"
}

# === 2. Windows Defender Status ===
Log "`nChecking Windows Defender status..."
try {
    $defender = Get-MpComputerStatus
    Log " - AMServiceEnabled: $($defender.AMServiceEnabled)"
    Log " - RealTimeProtectionEnabled: $($defender.RealTimeProtectionEnabled)"
    Log " - AntivirusEnabled: $($defender.AntivirusEnabled)"
    Log " - Signature Version: $($defender.AntispywareSignatureVersion)"
} catch {
    Log "⚠️ Unable to query Defender status: $_"
}

# === 3. Check for Vulnerable Services (SMBv1, Telnet, RDP) ===
Log "`nChecking for risky services or features..."

# SMBv1
$smbv1 = Get-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol"
if ($smbv1.State -eq "Enabled") {
    Log "❗ SMBv1 is ENABLED – Vulnerable!"
} else {
    Log "✅ SMBv1 is Disabled"
}

# Telnet
$telnet = Get-WindowsFeature -Name "Telnet-Client"
if ($telnet.Installed) {
    Log "❗ Telnet Client is ENABLED – Not Secure"
} else {
    Log "✅ Telnet Client is Disabled"
}

# RDP
$rdpStatus = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections"
if ($rdpStatus.fDenyTSConnections -eq 0) {
    Log "⚠️ RDP is ENABLED"
} else {
    Log "✅ RDP is Disabled"
}

# === 4. List Installed Software (to match against CVEs manually) ===
Log "`nInstalled Applications:"
Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |
    Select-Object DisplayName, DisplayVersion |
    Where-Object { $_.DisplayName } |
    ForEach-Object {
        Log " - $($_.DisplayName) $($_.DisplayVersion)"
    }

# === 5. Optional: Check Windows Defender Threats ===
Log "`nQuerying threat history from Defender..."
try {
    $threats = Get-MpThreatDetection
    if ($threats) {
        foreach ($threat in $threats) {
            Log "❗ Detected: $($threat.ThreatName) at $($threat.InitialDetectionTime)"
        }
    } else {
        Log "✅ No current threat detections"
    }
} catch {
    Log "⚠️ Unable to retrieve threat history"
}

Log "`n==== Scan Complete. Report saved to: $logFile ===="
