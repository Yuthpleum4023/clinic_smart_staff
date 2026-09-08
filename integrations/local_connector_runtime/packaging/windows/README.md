# Windows Packaging Foundation

This directory defines the production package boundary for Clinic Smart Staff Connector.

Production layout:
- app/
- node/
- service/
- config/
- state/
- logs/
- scripts/

Secrets must not be baked into the installer or committed config.

Expected protected service environment variables:
- CLINIC_CONNECTOR_TOKEN
- CLINIC_SOURCE_DB_PASSWORD

Do not make unsupported legacy patient-care Windows hosts a deployment requirement.
Prefer a supported Windows gateway/server on the same LAN when the legacy source database can be reached read-only.

The service manifest targets a WinSW-style wrapper. The actual signed wrapper binary is a packaging artifact and is intentionally not committed here.
