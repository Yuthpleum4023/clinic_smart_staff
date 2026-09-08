$ErrorActionPreference = "Stop"

$Base = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$ServiceExe = Join-Path $Base "service\ClinicSmartStaffConnectorService.exe"

if (-not (Test-Path $ServiceExe)) {
  throw "Service wrapper not found: $ServiceExe"
}

& $ServiceExe stop
& $ServiceExe uninstall

Write-Host "CLINIC_SMART_STAFF_CONNECTOR_SERVICE_UNINSTALLED=TRUE"
