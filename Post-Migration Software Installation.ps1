Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    [System.Windows.MessageBox]::Show("Please run this script as Administrator.", "Permission Required", "OK", "Warning")
    exit
}

$logFolder = "C:\Temp"
$installerFolder = Join-Path $logFolder "Installers"
if (-not (Test-Path $logFolder)) {
    New-Item -ItemType Directory -Path $logFolder | Out-Null
}
if (-not (Test-Path $installerFolder)) {
    New-Item -ItemType Directory -Path $installerFolder | Out-Null
}

$logFile = Join-Path $logFolder "AppInstall_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

$defaultApps = @(
    @{ Name = "Crowdstrike"; FilePath = "\\awsuse2file01.3mhealth.com\bedrock\Installs\Agents\Crowdstrike\WindowsSensor.exe"; Arguments = "/install /quiet /norestart CID=9785FF0D817B49B3B4B0D584B2D8BF23-B7" },
    @{ Name = "Splunk"; FilePath = "msiexec.exe"; MsiPath = "\\awsuse2file01.3mhealth.com\Installs\Splunk\splunkforwarder-9.2.1-78803f08aabb-x64-release.msi"; Arguments = "" },
    @{ Name = "Qualys"; FilePath = "\\awsuse2file01.3mhealth.com\bedrock\Installs\Agents\Qualys\QualysCloudAgent.exe"; Arguments = "/quiet CustomerId={6ee5d733-9e25-7597-8254-c36cfcfb4bed} ActivationId={a8e88c2c-9361-406c-8fc9-cefd8cdabc40} WebServiceUri=https://qagpublic.qg2.apps.qualys.com/CloudAgent/" },
    @{ Name = "SCCM"; FilePath = "\\awsuse2file01.3mhealth.com\bedrock\Installs\Agents\SCCM Client\Client\ccmsetup.exe"; Arguments = "/quiet /norestart /mp:https://MECMPRDPR3SEC1.3mhealth.com /skipprereq:silverlight.exe /forceinstall SMSSITECODE=PRH SMSMP=MECMPRDPR3SEC1.3mhealth.com FSP=MECMPRDPR3.3mhealth.com /UsePKICert /NoCRLCheck" }
)

$optionalApps = @(
    @{ Name = "Commvault"; FolderPath = "\\awsuse2file01.3mhealth.com\bedrock\Installs\Agents\Commvault_WinX64"; FilePath = "Setup.exe"; Arguments = "/silent /norestart" }
)

# Copy installer files to C:\Temp\Installers and update FilePath
foreach ($app in $defaultApps + $optionalApps) {
    if ($app.ContainsKey('MsiPath')) {
        $msiName = Split-Path $app.MsiPath -Leaf
        $localMsi = Join-Path $installerFolder $msiName
        try {
            Copy-Item -Path $app.MsiPath -Destination $localMsi -Force
            $app.Arguments = "/i \"$localMsi\" /qn /norestart AGREETOLICENSE=Yes RECEIVING_INDEXER=\"3mhealth.splunkcloud.com:9997\" DEPLOYMENT_SERVER=\"splunkcloudprufds.3mhealth.com:8089\" SPLUNKUSERNAME=\"splunkadmin\" SPLUNKPASSWORD=\"qfZB-YwWTpafQP!X!-9BJFZ3jvshEFYg\""
        } catch {
            Write-Host "Failed to copy MSI for $($app.Name): $_" -ForegroundColor Red
        }
    }
    elseif ($app.ContainsKey('FolderPath')) {
        $folderName = Split-Path $app.FolderPath -Leaf
        $localFolder = Join-Path $installerFolder $folderName
        try {
            Copy-Item -Path $app.FolderPath -Destination $localFolder -Recurse -Force
            $app.FilePath = Join-Path $localFolder $app.FilePath
        } catch {
            Write-Host "Failed to copy folder for $($app.Name): $_" -ForegroundColor Red
        }
    }
    elseif ($app.FilePath -ne "msiexec.exe" -and $app.FilePath -like "\\*") {
        $fileName = Split-Path $app.FilePath -Leaf
        $localPath = Join-Path $installerFolder $fileName
        try {
            Copy-Item -Path $app.FilePath -Destination $localPath -Recurse -Force
            $app.FilePath = $localPath
        } catch {
            Write-Host "Failed to copy $($app.Name) to local folder: $_" -ForegroundColor Red
        }
    }
}

# Cleanup function to remove installers after installation
function Cleanup-Installers {
    Get-ChildItem -Path $installerFolder -Recurse -Force | Where-Object { $_.FullName -ne $logFile } | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    Write-Host "Cleaned up installer files. Log file remains at: $logFile"
}

function Log {
    param([string]$Message, [ConsoleColor]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp - $Message"
    Write-Host $entry -ForegroundColor $Color
    Add-Content -Path $logFile -Value $entry
}

function Show-InstallSummary {
    param([string[]]$SummaryLines)

    $summaryWindow = New-Object System.Windows.Window
    $summaryWindow.Title = "Installation Summary"
    $summaryWindow.Width = 500
    $summaryWindow.Height = 400
    $summaryWindow.WindowStartupLocation = 'CenterScreen'

    $stackPanel = New-Object System.Windows.Controls.StackPanel

    $textBox = New-Object System.Windows.Controls.TextBox
    $textBox.Text = ($SummaryLines -join "`r`n")
    $textBox.IsReadOnly = $true
    $textBox.VerticalScrollBarVisibility = 'Auto'
    $textBox.TextWrapping = 'Wrap'
    $textBox.Margin = '10'

    $viewLogButton = New-Object System.Windows.Controls.Button
    $viewLogButton.Content = "Open Log File"
    $viewLogButton.Margin = '10'
    $viewLogButton.Width = 120
    $viewLogButton.HorizontalAlignment = 'Center'
    $viewLogButton.Add_Click({ Start-Process notepad.exe $logFile })

    $stackPanel.Children.Add($textBox)
    $stackPanel.Children.Add($viewLogButton)

    $summaryWindow.Content = $stackPanel
    $summaryWindow.ShowDialog() | Out-Null
}

function Install-App {
    param (
        [string]$Name,
        [string]$FilePath,
        [string]$Arguments,
        [System.Windows.Controls.ProgressBar]$ProgressBar,
        [int]$ProgressStep,
        [System.Windows.Controls.TextBlock]$StatusText
    )

    $StatusText.Text = "Installing: $Name"
    Log ("`nInstalling: {0}..." -f $Name) Yellow
    $ProgressBar.Value += $ProgressStep

    if (Test-Path $FilePath) {
        try {
            $workingDir = Split-Path -Parent $FilePath
            $proc = Start-Process -FilePath $FilePath -ArgumentList $Arguments -WorkingDirectory $workingDir -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop
            if ($proc.ExitCode -eq 0) {
                Log ("✔️ {0} installed successfully." -f $Name) Green
                return $true
            } else {
                Log ("❌ {0} failed with exit code {1}." -f $Name, $proc.ExitCode) Red
                return $false
            }
        } catch {
            Log ("❌ Error installing {0}: {1}" -f $Name, $_) Red
            return $false
        }
    } else {
        Log ("❌ File not found for {0}: {1}" -f $Name, $FilePath) Red
        return $false
    }
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="Application Installer" SizeToContent="WidthAndHeight" WindowStartupLocation="CenterScreen">
  <StackPanel Margin="20" HorizontalAlignment="Center">
    <TextBlock FontSize="18" FontWeight="Bold" Text="Software Installer" Margin="0,0,0,10" TextAlignment="Center"/>
    <TextBlock FontSize="12" TextWrapping="Wrap" TextAlignment="Center"
               Text="Crowdstrike, SCCM, Splunk, and Qualys will be installed by default. Select any additional applications below:" Margin="0,0,0,15"/>
    <CheckBox Name="CommvaultBox" Content="Commvault" Margin="0,0,0,5"/>
    <CheckBox Name="SkipRebootBox" Content="Skip Reboot After Install" Margin="0,10,0,5"/>
    <TextBlock Name="StatusText" FontSize="18" FontWeight="Bold" TextAlignment="Center" Margin="0,10,0,5"/>
    <ProgressBar Name="InstallProgress" Width="300" Height="20" Margin="0,10,0,0"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,10,0,0">
      <Button Name="InstallButton" Content="Install Selected" Width="120" Margin="5"/>
      <Button Name="ExitButton" Content="Exit" Width="80" Margin="5"/>
    </StackPanel>
  </StackPanel>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$gui = [Windows.Markup.XamlReader]::Load($reader)
$commvaultBox = $gui.FindName("CommvaultBox")
$skipRebootBox = $gui.FindName("SkipRebootBox")
$installButton = $gui.FindName("InstallButton")
$exitButton = $gui.FindName("ExitButton")
$progressBar = $gui.FindName("InstallProgress")
$statusText = $gui.FindName("StatusText")

$exitButton.Add_Click({ $gui.Close(); exit })

$installButton.Add_Click({
    $installButton.IsEnabled = $false
    $exitButton.IsEnabled = $false
    $progressBar.Minimum = 0
    $statusText.Text = "Starting installation..."
    $startTime = Get-Date

    $installQueue = @()
    $installQueue += $defaultApps
    if ($commvaultBox.IsChecked) {
        $installQueue += $optionalApps | Where-Object { $_.Name -eq "Commvault" }
    }

    $progressBar.Maximum = $installQueue.Count
    $progressStep = 1
    $allSuccess = $true

    foreach ($app in $installQueue) {
        $success = Install-App -Name $app.Name -FilePath $app.FilePath -Arguments $app.Arguments -ProgressBar $progressBar -ProgressStep $progressStep -StatusText $statusText
        if (-not $success) { $allSuccess = $false }
    }

    $progressBar.Value = $progressBar.Maximum
    $elapsed = (Get-Date) - $startTime
    $statusText.Text = "Install complete. Elapsed time: $($elapsed.ToString("hh\:mm\:ss"))"
    Log "\n✅ Elapsed time: $($elapsed.ToString("hh\:mm\:ss"))"

    $summaryLines = @()
    foreach ($app in $installQueue) {
        $status = if ((Select-String -Path $logFile -Pattern "✔️ $($app.Name) installed successfully.")) { "✔️ Success" } else { "❌ Failed" }
        $summaryLines += "$($app.Name): $status"
    }

    Show-InstallSummary -SummaryLines $summaryLines

    if ($allSuccess -and -not $skipRebootBox.IsChecked) {
        Log "\n✅ All apps installed successfully. Rebooting in 10 seconds..." Cyan
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    } elseif ($allSuccess) {
        Log "\n✅ All apps installed successfully. Reboot skipped per user choice." Cyan
    } else {
        [System.Windows.MessageBox]::Show("One or more applications failed. Check the log file in C:\\Temp.", "Install Error", "OK", "Error")
        Log "\n⚠️ One or more apps failed. Reboot aborted." Red
    }
})

$gui.ShowDialog() | Out-Null
