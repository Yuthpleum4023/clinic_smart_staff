$ErrorActionPreference = "Stop"

$Base = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$ServiceExe = Join-Path $Base "service\ClinicSmartStaffConnectorService.exe"
$ServiceXml = Join-Path $Base "service\ClinicSmartStaffConnectorService.xml"
$Config = Join-Path $Base "config\connector-config.json"
$Node = Join-Path $Base "node\node.exe"
$Entrypoint = Join-Path $Base "app\bin\connector.js"

foreach ($required in @($ServiceExe, $ServiceXml, $Config, $Node, $Entrypoint)) {
  if (-not (Test-Path $required)) {
    throw "Required connector package file missing: $required"
  }
}

if (-not $env:CLINIC_CONNECTOR_TOKEN) {
  throw "CLINIC_CONNECTOR_TOKEN is not configured in the service environment."
}

if (-not $env:CLINIC_SOURCE_DB_PASSWORD) {
  throw "CLINIC_SOURCE_DB_PASSWORD is not configured in the service environment."
}

New-Item -ItemType Directory -Force -Path (Join-Path $Base "state") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Base "logs") | Out-Null

& $ServiceExe install
if ($LASTEXITCODE -ne 0) {
  throw "Connector service installation failed."
}

& $ServiceExe start
if ($LASTEXITCODE -ne 0) {
  throw "Connector service start failed."
}

Write-Host "CLINIC_SMART_STAFF_CONNECTOR_SERVICE_INSTALLED=TRUE"
