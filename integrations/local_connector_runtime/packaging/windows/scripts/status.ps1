$ErrorActionPreference = "SilentlyContinue"

$Service = Get-Service -Name "ClinicSmartStaffConnector"
$Base = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$HealthPath = Join-Path $Base "state\health.json"

if ($Service) {
  Write-Host ("SERVICE_STATUS=" + $Service.Status)
} else {
  Write-Host "SERVICE_STATUS=NOT_INSTALLED"
}

if (Test-Path $HealthPath) {
  Write-Host "HEALTH_FILE_PRESENT=TRUE"
  Get-Content $HealthPath
} else {
  Write-Host "HEALTH_FILE_PRESENT=FALSE"
}
