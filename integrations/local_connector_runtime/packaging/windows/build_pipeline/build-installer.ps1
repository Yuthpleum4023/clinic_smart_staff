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
  [string]$WorkRoot
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

& (Join-Path $PipelineRoot "write-checksums.ps1") `
  -ArtifactDirectory $DistRoot

Write-Host "CONNECTOR_INSTALLER_BUILD_COMPLETE=TRUE"
Write-Host ("DIST_ROOT=" + $DistRoot)
