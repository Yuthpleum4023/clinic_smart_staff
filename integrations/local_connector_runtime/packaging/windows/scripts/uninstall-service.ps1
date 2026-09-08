$ErrorActionPreference = "Stop"
$InstallRoot = Split-Path -Parent $PSScriptRoot
$ServiceExe = Join-Path $InstallRoot "ClinicSmartStaffConnectorService.exe"
if (-not (Test-Path $ServiceExe)) { throw "Service wrapper not found: $ServiceExe" }
$Existing = Get-Service -Name "ClinicSmartStaffConnector" -ErrorAction SilentlyContinue
if (-not $Existing) {
  Write-Host "CONNECTOR_SERVICE_NOT_INSTALLED=TRUE"
  exit 0
}
if ($Existing.Status -ne "Stopped") { & $ServiceExe stop }
& $ServiceExe uninstall
if ($LASTEXITCODE -ne 0) { throw "Connector service uninstall failed." }
Write-Host "CLINIC_SMART_STAFF_CONNECTOR_SERVICE_UNINSTALLED=TRUE"
