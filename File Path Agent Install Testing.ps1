# Get the Desktop path for the test log
$desktopPath = [Environment]::GetFolderPath("Desktop")
$logFile = Join-Path $desktopPath "AppInstall_TestLog_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

function Log {
    param ([string]$Message, [ConsoleColor]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp - $Message"
    Write-Host $entry -ForegroundColor $Color
    Add-Content -Path $logFile -Value $entry
}

Log "==== Application Path & Connection Test ====" Cyan

# Define applications and paths (same as full install)
$appsToTest = @(
    @{
        Name     = "Crowdstrike"
        FilePath = "\\awsuse2file01.3mhealth.com\bedrock\Installs\Agents\Crowdstrike\WindowsSensor.exe"
    },
    @{
        Name     = "Qualys"
        FilePath = "\\awsuse2file01.3mhealth.com\bedrock\Installs\Agents\Qualys\QualysCloudAgent.exe"
    },
    @{
        Name     = "SCCM"
        FilePath = "\\awsuse2file01.3mhealth.com\bedrock\Installs\Agents\SCCM Client\Client\ccmsetup.exe"
    }
    @{
        Name     = "Splunk"
        FilePath = "\\awsuse2file01.3mhealth.com\bedrock\Installs\Agents\Splunk\splunkforwarder-9.2.1-78803f08aabb-x64-release.msi"
    }
)

foreach ($app in $appsToTest) {
    $name = $app.Name
    $path = $app.FilePath

    Log "`nChecking: $name" Yellow

    if (Test-Path $path) {
        Log "✔️  Path exists: $path" Green

        try {
            if ((Get-Item $path).PSIsContainer) {
                Log "ℹ️  This is a folder. Access confirmed." Cyan
            } else {
                Log "ℹ️  This is a file. Size: $((Get-Item $path).Length / 1MB) MB" Cyan
            }
        }
        catch {
            Log "⚠️  Path exists but access denied or error reading: $_" Red
        }
    }
    else {
        Log "❌ Path not found or inaccessible: $path" Red
    }
}

Log "`n==== Test Complete ====" Cyan