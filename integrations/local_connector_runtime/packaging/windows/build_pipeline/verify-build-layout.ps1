$ErrorActionPreference = "Stop"

param(
  [Parameter(Mandatory=$true)]
  [string]$LayoutRoot
)

$Required = @(
  "app\bin\connector.js",
  "app\package.json",
  "node\node.exe",
  "service\ClinicSmartStaffConnectorService.exe",
  "service\ClinicSmartStaffConnectorService.xml",
  "config\connector-config.template.json",
  "scripts\install-service.ps1",
  "scripts\uninstall-service.ps1",
  "scripts\status.ps1"
)

foreach ($rel in $Required) {
  $path = Join-Path $LayoutRoot $rel

  if (-not (Test-Path $path)) {
    throw "Required package file missing: $rel"
  }
}

$ConfigText =
  Get-Content `
    (Join-Path $LayoutRoot "config\connector-config.template.json") `
    -Raw

if ($ConfigText -match '"password"\s*:\s*"[^"]+"') {
  throw "Plaintext database password found in packaged config."
}

if ($ConfigText -match 'CLINIC_CONNECTOR_TOKEN\s*[:=]\s*[^"]+') {
  throw "Connector credential value must not be embedded."
}

Write-Host "CONNECTOR_BUILD_LAYOUT_VERIFIED=TRUE"
Write-Host "PLAINTEXT_DB_PASSWORD_IN_LAYOUT=FALSE"
Write-Host "CONNECTOR_TOKEN_VALUE_IN_LAYOUT=FALSE"
