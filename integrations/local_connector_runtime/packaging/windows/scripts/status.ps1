$ErrorActionPreference = "SilentlyContinue"
$InstallRoot = Split-Path -Parent $PSScriptRoot
$HealthPath = Join-Path $InstallRoot "state\health.json"
$Service = Get-Service -Name "ClinicSmartStaffConnector" -ErrorAction SilentlyContinue
if ($Service) { Write-Host ("SERVICE_STATUS=" + $Service.Status) } else { Write-Host "SERVICE_STATUS=NOT_INSTALLED" }
if (Test-Path $HealthPath) {
  Write-Host "HEALTH_FILE_PRESENT=TRUE"
  Get-Content $HealthPath
} else {
  Write-Host "HEALTH_FILE_PRESENT=FALSE"
}
