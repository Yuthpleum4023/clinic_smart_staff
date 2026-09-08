param(
  [Parameter(Mandatory=$true)]
  [string]$RuntimeRoot,

  [Parameter(Mandatory=$true)]
  [string]$BuildInputsRoot,

  [Parameter(Mandatory=$true)]
  [string]$OutputRoot
)

$ErrorActionPreference = "Stop"

$RuntimeRoot = (Resolve-Path $RuntimeRoot).Path
$BuildInputsRoot = (Resolve-Path $BuildInputsRoot).Path

$NodeInput = Join-Path $BuildInputsRoot "node"
$WinSwInput = Join-Path $BuildInputsRoot "ClinicSmartStaffConnectorService.exe"

if (-not (Test-Path (Join-Path $NodeInput "node.exe"))) {
  throw "Pinned Node runtime input missing: $NodeInput\node.exe"
}

if (-not (Test-Path $WinSwInput)) {
  throw "Pinned WinSW input missing: $WinSwInput"
}

if (Test-Path $OutputRoot) {
  Remove-Item -Recurse -Force $OutputRoot
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$Dirs = @(
  "app",
  "node",
  "service",
  "config",
  "state",
  "logs",
  "scripts"
)

foreach ($dir in $Dirs) {
  New-Item -ItemType Directory -Force -Path (Join-Path $OutputRoot $dir) | Out-Null
}

Copy-Item -Recurse -Force `
  (Join-Path $RuntimeRoot "bin") `
  (Join-Path $OutputRoot "app")

Copy-Item -Recurse -Force `
  (Join-Path $RuntimeRoot "src") `
  (Join-Path $OutputRoot "app")

Copy-Item -Force `
  (Join-Path $RuntimeRoot "package.json") `
  (Join-Path $OutputRoot "app\package.json")

if (-not (Test-Path (Join-Path $RuntimeRoot "package-lock.json"))) {
  throw "package-lock.json is required for deterministic production dependency installation."
}

Copy-Item -Force `
  (Join-Path $RuntimeRoot "package-lock.json") `
  (Join-Path $OutputRoot "app\package-lock.json")

Copy-Item -Recurse -Force `
  (Join-Path $NodeInput "*") `
  (Join-Path $OutputRoot "node")

$NpmCmd = Join-Path $OutputRoot "node\npm.cmd"
if (-not (Test-Path $NpmCmd)) {
  throw "Bundled Node runtime must include npm.cmd."
}

Push-Location (Join-Path $OutputRoot "app")
try {
  & $NpmCmd ci --omit=dev --ignore-scripts --no-audit --no-fund
  if ($LASTEXITCODE -ne 0) { throw "Production npm dependency installation failed." }
}
finally {
  Pop-Location
}

Copy-Item -Force `
  $WinSwInput `
  (Join-Path $OutputRoot "ClinicSmartStaffConnectorService.exe")

Copy-Item -Force `
  (Join-Path $RuntimeRoot "packaging\windows\service\ClinicSmartStaffConnectorService.xml") `
  (Join-Path $OutputRoot "ClinicSmartStaffConnectorService.xml")

Copy-Item -Force `
  (Join-Path $RuntimeRoot "packaging\windows\templates\connector-config.template.json") `
  (Join-Path $OutputRoot "config\connector-config.template.json")

Copy-Item -Force `
  (Join-Path $RuntimeRoot "packaging\windows\scripts\install-service.ps1") `
  (Join-Path $OutputRoot "scripts\install-service.ps1")

Copy-Item -Force `
  (Join-Path $RuntimeRoot "packaging\windows\scripts\uninstall-service.ps1") `
  (Join-Path $OutputRoot "scripts\uninstall-service.ps1")

Copy-Item -Force `
  (Join-Path $RuntimeRoot "packaging\windows\scripts\status.ps1") `
  (Join-Path $OutputRoot "scripts\status.ps1")

Copy-Item -Force `
  (Join-Path $RuntimeRoot "packaging\windows\scripts\validate-config.ps1") `
  (Join-Path $OutputRoot "scripts\validate-config.ps1")

Copy-Item -Force `
  (Join-Path $RuntimeRoot "packaging\windows\scripts\provision-and-start-service.ps1") `
  (Join-Path $OutputRoot "scripts\provision-and-start-service.ps1")

Write-Host "CONNECTOR_BUILD_LAYOUT_CREATED=TRUE"
Write-Host ("OUTPUT_ROOT=" + $OutputRoot)
