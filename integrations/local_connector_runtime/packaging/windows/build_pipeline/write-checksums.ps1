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

$ManifestText =
  if ($Lines.Count -eq 0) {
    ""
  } else {
    ($Lines -join "`n") + "`n"
  }

[System.IO.File]::WriteAllText(
  $Output,
  $ManifestText,
  [System.Text.Encoding]::ASCII
)

Write-Host "CONNECTOR_SHA256_MANIFEST_CREATED=TRUE"
Write-Host ("CHECKSUM_FILE=" + $Output)
