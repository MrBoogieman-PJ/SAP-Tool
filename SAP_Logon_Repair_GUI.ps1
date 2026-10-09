<#
SAP Logon Repair GUI Tool
Repairs missing SAP Logon instances using deployment-specific configuration.
Run as the affected Windows user. Admin rights are not normally required for HKCU SAP settings.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# -----------------------------
# Configuration
# -----------------------------
$ConfigPath = Join-Path $PSScriptRoot 'SAP_Logon_Repair.config.json'
$RequiredSapGuiText = 'Not specified'
$SapShare = ''
$SapXml = ''
$SupportInstructions = 'Contact your local SAP support team.'
$LogFile = Join-Path $env:TEMP 'SAP_Logon_Repair_GUI.log'

if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
        if (-not [string]::IsNullOrWhiteSpace($config.RequiredSapGuiText)) { $RequiredSapGuiText = $config.RequiredSapGuiText }
        if (-not [string]::IsNullOrWhiteSpace($config.SapShare)) { $SapShare = $config.SapShare }
        if (-not [string]::IsNullOrWhiteSpace($config.SapXml)) { $SapXml = $config.SapXml }
        if (-not [string]::IsNullOrWhiteSpace($config.SupportInstructions)) { $SupportInstructions = $config.SupportInstructions }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not read configuration file:`n$ConfigPath`n`n$($_.Exception.Message)", 'Invalid Configuration', 'OK', 'Error') | Out-Null
        exit 1
    }
}

# -----------------------------
# Helper Functions
# -----------------------------
function Write-ToolLog {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$timestamp [$Level] $Message"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8

    if ($script:txtLog) {
        $script:txtLog.AppendText($line + [Environment]::NewLine)
        $script:txtLog.SelectionStart = $script:txtLog.Text.Length
        $script:txtLog.ScrollToCaret()
    }
}

function Set-Status {
    param(
        [string]$Text,
        [System.Drawing.Color]$Color = [System.Drawing.Color]::Black
    )
    $script:lblStatus.Text = "Status: $Text"
    $script:lblStatus.ForeColor = $Color
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-SapLogonPath {
    $knownPaths = @(
        'C:\Program Files (x86)\SAP\FrontEnd\SAPgui\saplogon.exe',
        'C:\Program Files\SAP\FrontEnd\SAPgui\saplogon.exe'
    )

    foreach ($path in $knownPaths) {
        if (Test-Path $path) { return $path }
    }

    # Fallback: check common SAP install roots only, not full drive recursion.
    $roots = @(
        'C:\Program Files (x86)\SAP',
        'C:\Program Files\SAP'
    )

    foreach ($root in $roots) {
        if (Test-Path $root) {
            $found = Get-ChildItem -Path $root -Filter 'saplogon.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { return $found.FullName }
        }
    }

    return $null
}

function Get-SapGuiInstallInfo {
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($path in $registryPaths) {
        try {
            $apps = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match 'SAP GUI|SAP Front End|SAPgui' } |
                Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation
            if ($apps) { return $apps }
        }
        catch { }
    }

    return $null
}

function Check-SapGui {
    Set-Status 'Checking SAP GUI installation...' ([System.Drawing.Color]::DarkBlue)
    Write-ToolLog 'Checking SAP GUI installation.'

    $sapPath = Get-SapLogonPath
    $installInfo = Get-SapGuiInstallInfo

    if ($sapPath) {
        Write-ToolLog "SAP Logon executable found: $sapPath" 'PASS'
        try {
            $version = (Get-Item $sapPath).VersionInfo.ProductVersion
            if ($version) { Write-ToolLog "SAP Logon file product version: $version" }
        }
        catch { Write-ToolLog "Could not read file version: $($_.Exception.Message)" 'WARN' }
    }
    else {
        Write-ToolLog "SAP Logon executable was not found. Required version: $RequiredSapGuiText" 'FAIL'
        Set-Status 'SAP Logon not found' ([System.Drawing.Color]::Red)
        [System.Windows.Forms.MessageBox]::Show("SAP Logon was not found.`n`nInstall the required SAP GUI version using your organization's approved software source:`n$RequiredSapGuiText", 'SAP GUI Not Found', 'OK', 'Error') | Out-Null
        return $false
    }

    if ($installInfo) {
        foreach ($app in $installInfo) {
            Write-ToolLog "Installed SAP component: $($app.DisplayName) | Version: $($app.DisplayVersion) | Location: $($app.InstallLocation)"
        }
    }
    else {
        Write-ToolLog 'SAP installation details were not found in uninstall registry. SAP executable check passed.' 'WARN'
    }

    Set-Status 'SAP GUI check completed' ([System.Drawing.Color]::Green)
    return $true
}

function Check-ShareAccess {
    Set-Status 'Checking SAP landscape share access...' ([System.Drawing.Color]::DarkBlue)
    Write-ToolLog "Checking access to SAP share: $SapShare"

    if (Test-Path $SapShare) {
        Write-ToolLog 'SAP landscape share is accessible.' 'PASS'
        if (Test-Path $SapXml) {
            Write-ToolLog "SAPUILandscape.xml found: $SapXml" 'PASS'
            Set-Status 'SAP share and XML are accessible' ([System.Drawing.Color]::Green)
            return $true
        }
        else {
            Write-ToolLog "SAP share is accessible but SAPUILandscape.xml was not found: $SapXml" 'FAIL'
            Set-Status 'SAP XML file not found' ([System.Drawing.Color]::Red)
            [System.Windows.Forms.MessageBox]::Show("SAP share is accessible, but SAPUILandscape.xml was not found:`n$SapXml", 'SAP XML Missing', 'OK', 'Warning') | Out-Null
            return $false
        }
    }
    else {
        Write-ToolLog "SAP landscape share is inaccessible: $SapShare" 'FAIL'
        Set-Status 'SAP share inaccessible' ([System.Drawing.Color]::Red)
            [System.Windows.Forms.MessageBox]::Show("Cannot access the SAP landscape path:`n$SapShare`n`n$SupportInstructions", 'SAP Share Inaccessible', 'OK', 'Error') | Out-Null
        return $false
    }
}

function Close-SapLogon {
    Write-ToolLog 'Checking if SAP Logon is running.'
    $processes = Get-Process -Name 'saplogon' -ErrorAction SilentlyContinue
    if ($processes) {
        foreach ($proc in $processes) {
            try {
                Write-ToolLog "Closing SAP Logon process ID $($proc.Id)."
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            }
            catch {
                Write-ToolLog "Failed to close SAP Logon process ID $($proc.Id): $($_.Exception.Message)" 'WARN'
            }
        }
    }
    else {
        Write-ToolLog 'SAP Logon is not currently running.'
    }
}

function Backup-SapRegistryKey {
    $backupFolder = Join-Path $env:TEMP 'SAP_Logon_Repair_Backup'
    if (!(Test-Path $backupFolder)) { New-Item -Path $backupFolder -ItemType Directory -Force | Out-Null }
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupFile = Join-Path $backupFolder "SAP_HKCU_Backup_$timestamp.reg"

    try {
        & reg.exe export 'HKCU\Software\SAP' $backupFile /y | Out-Null
        Write-ToolLog "SAP registry backup created: $backupFile" 'PASS'
    }
    catch {
        Write-ToolLog "SAP registry backup failed or key does not exist yet: $($_.Exception.Message)" 'WARN'
    }
}

function Set-SapXmlConfiguration {
    Set-Status 'Updating SAP XML configuration...' ([System.Drawing.Color]::DarkBlue)
    Write-ToolLog 'Starting SAP XML configuration update.'

    if (!(Check-ShareAccess)) { return $false }

    Close-SapLogon
    Backup-SapRegistryKey

    # SAP GUI installations can store the setting under different HKCU paths depending on version/patch.
    # This tool writes the commonly used SAP Logon option values under HKCU. It does not modify machine-wide settings.
    $candidateKeys = @(
        'HKCU:\Software\SAP\SAPLogon',
        'HKCU:\Software\SAP\SAPLogon\Options',
        'HKCU:\Software\SAP\General\Appearance',
        'HKCU:\Software\SAP\SAPGUI Front\SAP Frontend Server\Security'
    )

    foreach ($key in $candidateKeys) {
        if (!(Test-Path $key)) {
            try {
                New-Item -Path $key -Force | Out-Null
                Write-ToolLog "Created registry key: $key"
            }
            catch {
                Write-ToolLog "Could not create registry key $key : $($_.Exception.Message)" 'WARN'
            }
        }
    }

    $valuesToSet = @(
        @{ Path = 'HKCU:\Software\SAP\SAPLogon'; Name = 'LandscapeFileOnServer'; Value = $SapXml },
        @{ Path = 'HKCU:\Software\SAP\SAPLogon\Options'; Name = 'LandscapeFileOnServer'; Value = $SapXml },
        @{ Path = 'HKCU:\Software\SAP\SAPLogon\Options'; Name = 'XMLConfigurationFileOnServer'; Value = $SapXml },
        @{ Path = 'HKCU:\Software\SAP\SAPLogon\Options'; Name = 'ServerConfigurationFile'; Value = $SapXml },
        @{ Path = 'HKCU:\Software\SAP\SAPLogon\Options'; Name = 'SAPUILandscapeXmlFileOnServer'; Value = $SapXml }
    )

    foreach ($item in $valuesToSet) {
        try {
            New-ItemProperty -Path $item.Path -Name $item.Name -Value $item.Value -PropertyType String -Force | Out-Null
            Write-ToolLog "Set registry value: $($item.Path)\$($item.Name) = $($item.Value)" 'PASS'
        }
        catch {
            Write-ToolLog "Failed to set registry value $($item.Path)\$($item.Name): $($_.Exception.Message)" 'WARN'
        }
    }

    Set-Status 'SAP XML configuration update completed' ([System.Drawing.Color]::Green)
    return $true
}

function Find-RefreshSettingsShortcut {
    $startMenuPaths = @(
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
    )

    foreach ($base in $startMenuPaths) {
        if (Test-Path $base) {
            $shortcut = Get-ChildItem -Path $base -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match 'Refresh Settings|Refresh.*SAP|SAP.*Refresh' } |
                Select-Object -First 1
            if ($shortcut) { return $shortcut.FullName }
        }
    }

    return $null
}

function Run-RefreshSettings {
    Set-Status 'Running Refresh Settings...' ([System.Drawing.Color]::DarkBlue)
    Write-ToolLog 'Attempting to launch Refresh Settings from Start Menu.'

    $shortcut = Find-RefreshSettingsShortcut
    if ($shortcut) {
        try {
            Start-Process -FilePath $shortcut
            Write-ToolLog "Refresh Settings shortcut launched: $shortcut" 'PASS'
            Set-Status 'Refresh Settings launched' ([System.Drawing.Color]::Green)
            return $true
        }
        catch {
            Write-ToolLog "Failed to launch Refresh Settings shortcut: $($_.Exception.Message)" 'WARN'
        }
    }
    else {
        Write-ToolLog 'Refresh Settings shortcut was not found in Start Menu.' 'WARN'
    }

    # Fallback: launch SAP workstation check tool if present.
    $possibleExecutables = @(
        'C:\Program Files (x86)\SAP\FrontEnd\SAPgui\NwSapSetup\NwCheckWorkstation.exe',
        'C:\Program Files\SAP\FrontEnd\SAPgui\NwSapSetup\NwCheckWorkstation.exe',
        'C:\Program Files (x86)\SAP\SAPsetup\setup\NwCheckWorkstation.exe',
        'C:\Program Files\SAP\SAPsetup\setup\NwCheckWorkstation.exe'
    )

    foreach ($exe in $possibleExecutables) {
        if (Test-Path $exe) {
            try {
                Start-Process -FilePath $exe
                Write-ToolLog "Fallback workstation check launched: $exe" 'PASS'
                Set-Status 'SAP workstation check launched' ([System.Drawing.Color]::Green)
                return $true
            }
            catch {
                Write-ToolLog "Failed to launch fallback tool $exe : $($_.Exception.Message)" 'WARN'
            }
        }
    }

    Set-Status 'Refresh Settings not found' ([System.Drawing.Color]::OrangeRed)
    [System.Windows.Forms.MessageBox]::Show('Refresh Settings shortcut was not found. Please run Refresh Settings manually from Start Menu if available.', 'Refresh Settings Not Found', 'OK', 'Information') | Out-Null
    return $false
}

function Open-SapLogon {
    Set-Status 'Opening SAP Logon...' ([System.Drawing.Color]::DarkBlue)
    $sapPath = Get-SapLogonPath
    if ($sapPath) {
        try {
            Start-Process -FilePath $sapPath
            Write-ToolLog "SAP Logon opened: $sapPath" 'PASS'
            Set-Status 'SAP Logon opened' ([System.Drawing.Color]::Green)
            return $true
        }
        catch {
            Write-ToolLog "Failed to open SAP Logon: $($_.Exception.Message)" 'FAIL'
            Set-Status 'Failed to open SAP Logon' ([System.Drawing.Color]::Red)
            return $false
        }
    }
    else {
        Write-ToolLog 'SAP Logon executable not found.' 'FAIL'
        Set-Status 'SAP Logon not found' ([System.Drawing.Color]::Red)
        return $false
    }
}

function Run-FullRepair {
    Set-Status 'Running full SAP repair...' ([System.Drawing.Color]::DarkBlue)
    Write-ToolLog '===== FULL SAP LOGON REPAIR STARTED ====='

    $sapOk = Check-SapGui
    if (-not $sapOk) {
        Write-ToolLog 'Full repair stopped because SAP GUI check failed.' 'FAIL'
        return
    }

    $xmlOk = Set-SapXmlConfiguration
    if (-not $xmlOk) {
        Write-ToolLog 'Full repair stopped because SAP XML configuration update failed.' 'FAIL'
        return
    }

    Run-RefreshSettings | Out-Null
    Start-Sleep -Seconds 2
    Open-SapLogon | Out-Null

    Write-ToolLog '===== FULL SAP LOGON REPAIR COMPLETED =====' 'PASS'
    Set-Status 'Full repair completed' ([System.Drawing.Color]::Green)
    [System.Windows.Forms.MessageBox]::Show("SAP Logon repair completed.`n`nPlease verify that SAP instances are now listed in SAP Logon.`n`nLog file:`n$LogFile", 'Repair Completed', 'OK', 'Information') | Out-Null
}

function Copy-LogToClipboard {
    if (Test-Path $LogFile) {
        $content = Get-Content -Path $LogFile -Raw -ErrorAction SilentlyContinue
        if ($content) {
            [System.Windows.Forms.Clipboard]::SetText($content)
            Write-ToolLog 'Log copied to clipboard.' 'PASS'
            [System.Windows.Forms.MessageBox]::Show('Diagnostic log copied to clipboard.', 'Copied', 'OK', 'Information') | Out-Null
        }
    }
    else {
        [System.Windows.Forms.MessageBox]::Show('No log file found yet.', 'No Log', 'OK', 'Information') | Out-Null
    }
}

function Open-LogFile {
    if (Test-Path $LogFile) {
        Start-Process notepad.exe $LogFile
    }
    else {
        [System.Windows.Forms.MessageBox]::Show('No log file found yet.', 'No Log', 'OK', 'Information') | Out-Null
    }
}

# -----------------------------
# GUI
# -----------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'SAP Logon Repair Tool - No SAP Instances Listed'
$form.Size = New-Object System.Drawing.Size(900, 620)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(820, 560)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.BackColor = [System.Drawing.Color]::White

$title = New-Object System.Windows.Forms.Label
$title.Text = 'SAP Logon Repair Tool'
$title.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::FromArgb(0, 90, 158)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(20, 18)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'Fix issue: No SAP instances listed in SAP Logon'
$subtitle.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$subtitle.AutoSize = $true
$subtitle.Location = New-Object System.Drawing.Point(22, 55)
$form.Controls.Add($subtitle)

$infoBox = New-Object System.Windows.Forms.TextBox
$infoBox.Multiline = $true
$infoBox.ReadOnly = $true
$infoBox.BorderStyle = 'FixedSingle'
$infoBox.BackColor = [System.Drawing.Color]::FromArgb(245, 248, 250)
$infoBox.Location = New-Object System.Drawing.Point(20, 85)
$infoBox.Size = New-Object System.Drawing.Size(840, 80)
$infoBox.Text = "Required SAP GUI: $RequiredSapGuiText`r`nSAP XML Configuration File on Server:`r`n$SapXml`r`n$SupportInstructions"
$form.Controls.Add($infoBox)

$buttonPanel = New-Object System.Windows.Forms.Panel
$buttonPanel.Location = New-Object System.Drawing.Point(20, 180)
$buttonPanel.Size = New-Object System.Drawing.Size(840, 110)
$form.Controls.Add($buttonPanel)

function New-Button {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W = 160,
        [int]$H = 35
    )
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Object System.Drawing.Point($X, $Y)
    $btn.Size = New-Object System.Drawing.Size($W, $H)
    $btn.FlatStyle = 'System'
    return $btn
}

$btnCheckSap = New-Button 'Check SAP GUI' 0 0
$btnCheckShare = New-Button 'Check Share Access' 170 0
$btnRepairConfig = New-Button 'Repair Config' 340 0
$btnRefresh = New-Button 'Run Refresh Settings' 510 0
$btnOpenSap = New-Button 'Open SAP Logon' 680 0

$btnFullRepair = New-Button 'Run Full Repair' 0 50 200 40
$btnFullRepair.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
$btnCopyLog = New-Button 'Copy Log' 215 50 140 40
$btnOpenLog = New-Button 'Open Log' 365 50 140 40
$btnClearLog = New-Button 'Clear Screen' 515 50 140 40
$btnExit = New-Button 'Exit' 665 50 140 40

$buttonPanel.Controls.AddRange(@($btnCheckSap, $btnCheckShare, $btnRepairConfig, $btnRefresh, $btnOpenSap, $btnFullRepair, $btnCopyLog, $btnOpenLog, $btnClearLog, $btnExit))

$script:lblStatus = New-Object System.Windows.Forms.Label
$script:lblStatus.Text = 'Status: Ready'
$script:lblStatus.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$script:lblStatus.AutoSize = $true
$script:lblStatus.Location = New-Object System.Drawing.Point(20, 305)
$form.Controls.Add($script:lblStatus)

$script:txtLog = New-Object System.Windows.Forms.TextBox
$script:txtLog.Multiline = $true
$script:txtLog.ScrollBars = 'Vertical'
$script:txtLog.ReadOnly = $true
$script:txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$script:txtLog.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$script:txtLog.ForeColor = [System.Drawing.Color]::White
$script:txtLog.Location = New-Object System.Drawing.Point(20, 335)
$script:txtLog.Size = New-Object System.Drawing.Size(840, 210)
$form.Controls.Add($script:txtLog)

$footer = New-Object System.Windows.Forms.Label
$footer.Text = "Log location: $LogFile"
$footer.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$footer.ForeColor = [System.Drawing.Color]::DimGray
$footer.AutoSize = $true
$footer.Location = New-Object System.Drawing.Point(20, 552)
$form.Controls.Add($footer)

$btnCheckSap.Add_Click({ Check-SapGui | Out-Null })
$btnCheckShare.Add_Click({ Check-ShareAccess | Out-Null })
$btnRepairConfig.Add_Click({ Set-SapXmlConfiguration | Out-Null })
$btnRefresh.Add_Click({ Run-RefreshSettings | Out-Null })
$btnOpenSap.Add_Click({ Open-SapLogon | Out-Null })
$btnFullRepair.Add_Click({ Run-FullRepair })
$btnCopyLog.Add_Click({ Copy-LogToClipboard })
$btnOpenLog.Add_Click({ Open-LogFile })
$btnClearLog.Add_Click({ $script:txtLog.Clear(); Set-Status 'Ready' ([System.Drawing.Color]::Black) })
$btnExit.Add_Click({ $form.Close() })

$form.Add_Shown({
    Write-ToolLog 'SAP Logon Repair GUI launched.'
    Write-ToolLog "Required SAP GUI: $RequiredSapGuiText"
    Write-ToolLog "SAP XML configured target: $SapXml"
})

[void]$form.ShowDialog()
