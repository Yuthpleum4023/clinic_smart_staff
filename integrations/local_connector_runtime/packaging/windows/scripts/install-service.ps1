$ErrorActionPreference = "Stop"
$InstallRoot = Split-Path -Parent $PSScriptRoot
$ServiceExe = Join-Path $InstallRoot "ClinicSmartStaffConnectorService.exe"
$ServiceXml = Join-Path $InstallRoot "ClinicSmartStaffConnectorService.xml"
$Config = Join-Path $InstallRoot "config\connector-config.json"
$Node = Join-Path $InstallRoot "node\node.exe"
$Entrypoint = Join-Path $InstallRoot "app\bin\connector.js"

foreach ($required in @($ServiceExe,$ServiceXml,$Config,$Node,$Entrypoint)) {
  if (-not (Test-Path $required)) { throw "Required connector package file missing: $required" }
}

$Existing = Get-Service -Name "ClinicSmartStaffConnector" -ErrorAction SilentlyContinue
if ($Existing) {
  Write-Host "CONNECTOR_SERVICE_ALREADY_INSTALLED=TRUE"
  exit 0
}

& $ServiceExe install
if ($LASTEXITCODE -ne 0) { throw "Connector service installation failed." }
Write-Host "CLINIC_SMART_STAFF_CONNECTOR_SERVICE_INSTALLED=TRUE"
Write-Host "CONNECTOR_SERVICE_STARTED=FALSE"
