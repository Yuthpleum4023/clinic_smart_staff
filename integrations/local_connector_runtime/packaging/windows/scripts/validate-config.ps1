param([Parameter(Mandatory=$true)][string]$ConfigPath)
$ErrorActionPreference = "Stop"
if (-not (Test-Path $ConfigPath)) { throw "Connector config not found: $ConfigPath" }
$Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if ($null -ne $Config.clinicId) { throw "CLINIC_SCOPE_MUST_NOT_BE_CONFIGURED_LOCALLY" }
if ($null -ne $Config.connectorId) { throw "CONNECTOR_SCOPE_MUST_NOT_BE_CONFIGURED_LOCALLY" }
foreach ($field in @("baseUrl","connectorTokenEnv","driverId","adapterId","profileId","checkpointKey","checkpointFile","healthFile")) {
  if (-not $Config.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$Config.$field)) {
    throw "CONFIG_FIELD_REQUIRED:$field"
  }
}
if ($Config.connectorTokenEnv -ne "CLINIC_CONNECTOR_TOKEN") { throw "CONNECTOR_TOKEN_ENV_CONTRACT_INVALID" }
if (-not $Config.source) { throw "SOURCE_CONFIG_REQUIRED" }
if ($Config.source.passwordEnv -ne "CLINIC_SOURCE_DB_PASSWORD") { throw "SOURCE_DB_PASSWORD_ENV_CONTRACT_INVALID" }
foreach ($field in @("host","user")) {
  if (-not $Config.source.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$Config.source.$field)) {
    throw "SOURCE_FIELD_REQUIRED:$field"
  }
}
if (-not $Config.source.PSObject.Properties["port"]) {
  throw "SOURCE_FIELD_REQUIRED:port"
}
$SourcePort = 0
if (
  -not [int]::TryParse([string]$Config.source.port, [ref]$SourcePort) -or
  $SourcePort -le 0 -or
  $SourcePort -gt 65535
) {
  throw "SOURCE_PORT_INVALID"
}
if ($Config.PSObject.Properties["adapterProfile"]) { throw "ADAPTER_PROFILE_MUST_COME_FROM_VERIFIED_REGISTRY" }
if ($Config.source.PSObject.Properties["database"]) { throw "SOURCE_DATABASE_MUST_COME_FROM_VERIFIED_REGISTRY" }
if ($Config.source.PSObject.Properties["poll"]) { throw "SOURCE_POLL_MUST_COME_FROM_VERIFIED_REGISTRY" }
Write-Host "CONNECTOR_CONFIG_VALID=TRUE"
