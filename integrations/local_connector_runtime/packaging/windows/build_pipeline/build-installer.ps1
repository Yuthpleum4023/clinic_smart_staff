param(
  [Parameter(Mandatory=$true)]
  [string]$RuntimeRoot,

  [Parameter(Mandatory=$true)]
  [string]$BuildInputsRoot,

  [Parameter(Mandatory=$true)]
  [string]$InnoCompiler,

  [Parameter(Mandatory=$true)]
  [string]$Version,

  [Parameter(Mandatory=$true)]
  [string]$WorkRoot,

  [Parameter(Mandatory=$true)]
  [string]$SourceRepository,

  [Parameter(Mandatory=$true)]
  [string]$SourceCommit,

  [Parameter(Mandatory=$true)]
  [string]$SourceRef,

  [Parameter(Mandatory=$true)]
  [string]$WorkflowName,

  [Parameter(Mandatory=$true)]
  [string]$WorkflowRunId,

  [Parameter(Mandatory=$true)]
  [string]$WorkflowRunAttempt,

  [Parameter(Mandatory=$true)]
  [string]$NodeVersion,

  [Parameter(Mandatory=$true)]
  [string]$WinSwSha256
)

$ErrorActionPreference = "Stop"

$PipelineRoot =
  Join-Path $RuntimeRoot "packaging\windows\build_pipeline"

$LayoutRoot =
  Join-Path $WorkRoot "layout"

$DistRoot =
  Join-Path $WorkRoot "dist"

& (Join-Path $PipelineRoot "build-layout.ps1") `
  -RuntimeRoot $RuntimeRoot `
  -BuildInputsRoot $BuildInputsRoot `
  -OutputRoot $LayoutRoot

& (Join-Path $PipelineRoot "verify-build-layout.ps1") `
  -LayoutRoot $LayoutRoot

New-Item -ItemType Directory -Force -Path $DistRoot | Out-Null

$Iss =
  Join-Path $RuntimeRoot "packaging\windows\installer\ClinicSmartStaffConnector.iss"

& $InnoCompiler `
  "/DMyAppVersion=$Version" `
  "/DBuildRoot=$LayoutRoot" `
  "/DOutputRoot=$DistRoot" `
  $Iss

if ($LASTEXITCODE -ne 0) {
  throw "Inno Setup compilation failed."
}

if ($SourceCommit -notmatch '^[A-Fa-f0-9]{40}$') {
  throw "Source commit must be a full 40-character Git SHA."
}

if ($WinSwSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
  throw "WinSW SHA-256 must be a 64-character hash."
}

$ArtifactName = "ClinicSmartStaffConnectorSetup-$Version-x64.exe"
$Provenance = [ordered]@{
  schemaVersion = 1
  productName = "Clinic Smart Staff Connector"
  version = $Version
  artifact = $ArtifactName
  architecture = "x64"
  signed = $false
  source = [ordered]@{
    repository = $SourceRepository
    commit = $SourceCommit.ToLower()
    ref = $SourceRef
  }
  ci = [ordered]@{
    provider = "github_actions"
    workflow = $WorkflowName
    runId = $WorkflowRunId
    runAttempt = $WorkflowRunAttempt
    runner = "windows-2022"
  }
  buildInputs = [ordered]@{
    nodeVersion = $NodeVersion
    winSwSha256 = $WinSwSha256.ToLower()
  }
}
$ProvenancePath = Join-Path $DistRoot "BUILD-PROVENANCE.json"
$ProvenanceJson = $Provenance | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText(
  $ProvenancePath,
  $ProvenanceJson + "`n",
  [System.Text.UTF8Encoding]::new($false)
)

& (Join-Path $PipelineRoot "write-checksums.ps1") `
  -ArtifactDirectory $DistRoot

Write-Host "CONNECTOR_INSTALLER_BUILD_COMPLETE=TRUE"
Write-Host ("DIST_ROOT=" + $DistRoot)
