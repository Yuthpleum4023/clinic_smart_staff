# FD Real Connectivity Configuration

This contract prepares deployment coordinates for a real MySQL connectivity test. It does not connect to FD by itself.

Verified fixed coordinates:
- database: `FD5_5`
- port: `3306`

Deployment-owned coordinates:
- `FD_SOURCE_HOST`
- `FD_SOURCE_USER`

Secret:
- `CLINIC_SOURCE_DB_PASSWORD`

The generated JSON contains no password. A successful later connectivity test proves only network reachability, MySQL authentication, and connection/ping lifecycle. It does not prove movement semantics or enable production inventory ingestion.
