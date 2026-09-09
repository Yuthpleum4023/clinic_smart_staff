param([Parameter(Mandatory=$true)][string]$ConfigPath)
$ErrorActionPreference = "Stop"
if (-not (Test-Path $ConfigPath)) { throw "Connector config not found: $ConfigPath" }
$Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if ($null -ne $Config.clinicId) { throw "CLINIC_SCOPE_MUST_NOT_BE_CONFIGURED_LOCALLY" }
if ($null -ne $Config.connectorId) { throw "CONNECTOR_SCOPE_MUST_NOT_BE_CONFIGURED_LOCALLY" }
foreach ($field in @("baseUrl","connectorTokenEnv","driverId","adapterId","checkpointKey","checkpointFile","healthFile")) {
  if (-not $Config.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$Config.$field)) {
    throw "CONFIG_FIELD_REQUIRED:$field"
  }
}
if ($Config.connectorTokenEnv -ne "CLINIC_CONNECTOR_TOKEN") { throw "CONNECTOR_TOKEN_ENV_CONTRACT_INVALID" }
if (-not $Config.source) { throw "SOURCE_CONFIG_REQUIRED" }
if ($Config.source.passwordEnv -ne "CLINIC_SOURCE_DB_PASSWORD") { throw "SOURCE_DB_PASSWORD_ENV_CONTRACT_INVALID" }
if (-not $Config.source.poll) { throw "SOURCE_POLL_CONFIG_REQUIRED" }
foreach ($field in @("table","cursorColumn")) {
  if (-not $Config.source.poll.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$Config.source.poll.$field)) {
    throw "SOURCE_POLL_FIELD_REQUIRED:$field"
  }
}
if (-not $Config.source.poll.columns -or $Config.source.poll.columns.Count -lt 1) { throw "SOURCE_POLL_COLUMNS_REQUIRED" }
if (-not $Config.adapterProfile) { throw "ADAPTER_PROFILE_REQUIRED" }
if ($Config.adapterProfile.schemaVerified -ne $true) { throw "ADAPTER_SCHEMA_VERIFICATION_REQUIRED" }
Write-Host "CONNECTOR_CONFIG_VALID=TRUE"
