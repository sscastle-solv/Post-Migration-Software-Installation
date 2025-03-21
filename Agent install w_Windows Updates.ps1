# Set shared installer folder
$sharedFolder = "\\YourSharedPath\Installers"

# Get desktop path for log file
$desktopPath = [Environment]::GetFolderPath("Desktop")
$logFile = Join-Path $desktopPath "Install_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

# Function to log and display messages
function Log {
    param (
        [string]$Message,
        [ConsoleColor]$Color = "White"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp - $Message"
    Write-Host $entry -ForegroundColor $Color
    Add-Content -Path $logFile -Value $entry
}

# List of applications
$appsToInstall = @(
    @{ Name = "Crowdstrike"; File = "crowdstrike.exe"; Args = "/quiet" },
    @{ Name = "SCCM";        File = "sccm_setup.exe"; Args = "/silent" },
    @{ Name = "Splunk";      File = "splunkinstaller.msi"; Args = "/qn" },
    @{ Name = "Qualys";      File = "qualysagent.msi"; Args = "/qn" }
)

$allInstalledSuccessfully = $true
Log "`n==== Application Installation Started ====" Cyan

foreach ($app in $appsToInstall) {
    $appName = $app.Name
    $installerPath = Join-Path $sharedFolder $app.File
    $arguments = $app.Args

    Log "`nInstalling: $appName..." Yellow

    if (Test-Path $installerPath) {
        try {
            $process = Start-Process -FilePath $installerPath -ArgumentList $arguments -Wait -PassThru -ErrorAction Stop
            if ($process.ExitCode -eq 0) {
                Log "✔️  $appName installed successfully." Green
            } else {
                Log "❌  $appName failed with exit code $($process.ExitCode)." Red
                $allInstalledSuccessfully = $false
            }
        } catch {
            Log "❌  Error during $appName installation: $_" Red
            $allInstalledSuccessfully = $false
        }
    } else {
        Log "⚠️  Installer not found for $appName at $installerPath" Magenta
        $allInstalledSuccessfully = $false
    }
}

# Proceed with Windows Updates if all installs were successful
if ($allInstalledSuccessfully) {
    Log "`n==== Installing Windows Updates ====" Cyan

    try {
        # Import and install module silently if not available
        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null
            Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
        }

        Import-Module PSWindowsUpdate -Force
        Log "Checking for updates..."
        Install-WindowsUpdate -AcceptAll -IgnoreReboot -AutoReboot -Verbose -ErrorAction Stop | Out-File -Append -FilePath $logFile

        Log "✔️  Windows Updates installed." Green
    } catch {
        Log "❌  Failed to install Windows Updates: $_" Red
        $allInstalledSuccessfully = $false
    }
}

# Reboot if everything succeeded
if ($allInstalledSuccessfully) {
    Log "`n✅ All applications and updates installed successfully." Green
    Log "🔄 Rebooting in 10 seconds..." Cyan
    Start-Sleep -Seconds 10
    Restart-Computer -Force
} else {
    Log "`n⚠️ One or more tasks failed. Manual intervention required. Reboot canceled." Red
}
