$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'SAP Logon Repair requires Windows.'
}

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$source = 'https://raw.githubusercontent.com/MrBoogieman-PJ/SAP-Tool/main'
$installFolder = Join-Path $env:LOCALAPPDATA 'SAP-Logon-Repair'
$scriptPath = Join-Path $installFolder 'SAP_Logon_Repair_GUI.ps1'
$examplePath = Join-Path $installFolder 'SAP_Logon_Repair.config.example.json'
$configPath = Join-Path $installFolder 'SAP_Logon_Repair.config.json'

try {
    New-Item -Path $installFolder -ItemType Directory -Force | Out-Null

    Invoke-WebRequest -Uri "$source/SAP_Logon_Repair_GUI.ps1" -OutFile $scriptPath -UseBasicParsing
    Invoke-WebRequest -Uri "$source/SAP_Logon_Repair.config.example.json" -OutFile $examplePath -UseBasicParsing

    if (-not (Test-Path -LiteralPath $configPath)) {
        Copy-Item -LiteralPath $examplePath -Destination $configPath
        Write-Host 'First run: enter your organization-specific SAP paths in the config file, save it, then close Notepad.'
        Start-Process -FilePath notepad.exe -ArgumentList ('"{0}"' -f $configPath) -Wait
    }

    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($config.SapShare) -or
        [string]::IsNullOrWhiteSpace($config.SapXml) -or
        $config.SapShare -like '*server\share*' -or
        $config.SapXml -like '*server\share*') {
        throw "Set SapShare and SapXml to valid organization paths in: $configPath"
    }

    Start-Process -FilePath powershell.exe -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $scriptPath)
    )
}
catch {
    Write-Error "Could not start SAP Logon Repair: $($_.Exception.Message)"
    Write-Host "Install folder: $installFolder"
    exit 1
}