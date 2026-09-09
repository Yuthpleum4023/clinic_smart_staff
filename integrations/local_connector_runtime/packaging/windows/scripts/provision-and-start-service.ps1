param(
  [Parameter(Mandatory=$true)][string]$ConfigSource,
  [Parameter(Mandatory=$false)][SecureString]$ConnectorToken,
  [Parameter(Mandatory=$false)][SecureString]$SourceDbPassword
)
$ErrorActionPreference = "Stop"

$InstallRoot = Split-Path -Parent $PSScriptRoot
$ConfigDir = Join-Path $InstallRoot "config"
$ActiveConfig = Join-Path $ConfigDir "connector-config.json"
$ValidateScript = Join-Path $PSScriptRoot "validate-config.ps1"
$InstallScript = Join-Path $PSScriptRoot "install-service.ps1"
$ServiceExe = Join-Path $InstallRoot "ClinicSmartStaffConnectorService.exe"
$NodeExe = Join-Path $InstallRoot "node\node.exe"
$BootstrapScript = Join-Path $InstallRoot "app\bin\bootstrap-forward-only.js"

if (-not (Test-Path $NodeExe)) { throw "Bundled Node runtime not found: $NodeExe" }
if (-not (Test-Path $BootstrapScript)) { throw "Forward-only bootstrap command not found: $BootstrapScript" }

if (-not $ConnectorToken) { $ConnectorToken = Read-Host "Clinic Smart Staff connector token" -AsSecureString }
if (-not $SourceDbPassword) { $SourceDbPassword = Read-Host "Source database read-only password" -AsSecureString }

& $ValidateScript -ConfigPath $ConfigSource
New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
Copy-Item -LiteralPath $ConfigSource -Destination $ActiveConfig -Force
& $ValidateScript -ConfigPath $ActiveConfig

$TokenPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ConnectorToken)
$DbPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SourceDbPassword)
$TokenPlain = $null
$DbPlain = $null
$PreviousConnectorToken = $null
$PreviousSourceDbPassword = $null

try {
  $TokenPlain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($TokenPtr)
  $DbPlain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($DbPtr)
  if ([string]::IsNullOrWhiteSpace($TokenPlain)) { throw "CONNECTOR_TOKEN_REQUIRED" }
  if ([string]::IsNullOrWhiteSpace($DbPlain)) { throw "SOURCE_DB_PASSWORD_REQUIRED" }

  $PreviousConnectorToken = $env:CLINIC_CONNECTOR_TOKEN
  $PreviousSourceDbPassword = $env:CLINIC_SOURCE_DB_PASSWORD

  $env:CLINIC_CONNECTOR_TOKEN = $TokenPlain
  $env:CLINIC_SOURCE_DB_PASSWORD = $DbPlain

  try {
    Push-Location $InstallRoot
    try {
      & $NodeExe $BootstrapScript $ActiveConfig
      if ($LASTEXITCODE -ne 0) { throw "Forward-only checkpoint bootstrap failed." }
    }
    finally {
      Pop-Location
    }
  }
  finally {
    if ($null -eq $PreviousConnectorToken) {
      Remove-Item Env:CLINIC_CONNECTOR_TOKEN -ErrorAction SilentlyContinue
    }
    else {
      $env:CLINIC_CONNECTOR_TOKEN = $PreviousConnectorToken
    }

    if ($null -eq $PreviousSourceDbPassword) {
      Remove-Item Env:CLINIC_SOURCE_DB_PASSWORD -ErrorAction SilentlyContinue
    }
    else {
      $env:CLINIC_SOURCE_DB_PASSWORD = $PreviousSourceDbPassword
    }
  }

  & $InstallScript
  $ServiceKey = "HKLM:\SYSTEM\CurrentControlSet\Services\ClinicSmartStaffConnector"
  if (-not (Test-Path $ServiceKey)) { throw "Connector service registry key not found after install." }

  $EnvironmentValues = @(
    "CLINIC_CONNECTOR_TOKEN=$TokenPlain",
    "CLINIC_SOURCE_DB_PASSWORD=$DbPlain"
  )
  New-ItemProperty -Path $ServiceKey -Name "Environment" -PropertyType MultiString -Value $EnvironmentValues -Force | Out-Null

  & $ServiceExe start
  if ($LASTEXITCODE -ne 0) { throw "Connector service start failed." }

  Write-Host "CONNECTOR_PROVISIONING_COMPLETE=TRUE"
  Write-Host "CONNECTOR_CONFIG_ACTIVATED=TRUE"
  Write-Host "CONNECTOR_FORWARD_ONLY_CHECKPOINT_READY=TRUE"
  Write-Host "CONNECTOR_SERVICE_SECRETS_PROVISIONED=TRUE"
  Write-Host "CONNECTOR_SERVICE_STARTED=TRUE"
}
finally {
  if ($TokenPtr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($TokenPtr) }
  if ($DbPtr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($DbPtr) }
  $TokenPlain = $null
  $DbPlain = $null
  $PreviousConnectorToken = $null
  $PreviousSourceDbPassword = $null
}
