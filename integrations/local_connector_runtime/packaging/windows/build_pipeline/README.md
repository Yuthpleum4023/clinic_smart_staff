# Windows Installer Build Pipeline

This pipeline builds the distributable Clinic Smart Staff Connector installer on a supported Windows build host.

## Inputs

The build must receive these external inputs:

- a pinned Node.js Windows x64 runtime directory containing `node.exe`
- a pinned WinSW binary renamed to `ClinicSmartStaffConnectorService.exe`
- Inno Setup compiler (`ISCC.exe`)

Those binaries are build inputs, not source-controlled application code.

## Pipeline

1. `build-layout.ps1`
2. `verify-build-layout.ps1`
3. `ISCC.exe` compiles `ClinicSmartStaffConnector.iss`
4. `write-checksums.ps1` creates `SHA256SUMS.txt`

## Signing

V1 deliberately produces an unsigned installer.

Authenticode signing belongs to the next release-security checkpoint and must happen after successful installer build and before public distribution.

## Secrets

Connector credentials and source DB credentials must not be embedded in the installer, source repository, or template configuration.
