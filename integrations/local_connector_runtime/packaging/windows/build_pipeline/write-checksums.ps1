param(
  [Parameter(Mandatory=$true)]
  [string]$ArtifactDirectory
)

$ErrorActionPreference = "Stop"

$Output = Join-Path $ArtifactDirectory "SHA256SUMS.txt"

$Files =
  Get-ChildItem `
    -Path $ArtifactDirectory `
    -File `
    -Recurse |
  Where-Object {
    $_.FullName -ne $Output
  } |
  Sort-Object FullName

$Lines = @()

foreach ($file in $Files) {
  $hash =
    (Get-FileHash `
      -Algorithm SHA256 `
      -Path $file.FullName).Hash.ToLower()

  $relative =
    $file.FullName.Substring(
      $ArtifactDirectory.Length
    ).TrimStart("\") -replace "\\", "/"

  $Lines += "$hash  $relative"
}

Set-Content `
  -Path $Output `
  -Value $Lines `
  -Encoding ASCII

Write-Host "CONNECTOR_SHA256_MANIFEST_CREATED=TRUE"
Write-Host ("CHECKSUM_FILE=" + $Output)
