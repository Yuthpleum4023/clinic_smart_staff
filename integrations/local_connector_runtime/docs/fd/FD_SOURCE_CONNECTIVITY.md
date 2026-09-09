# FD Source Connectivity

This path tests only whether the connector host can establish
a MySQL connection to the FD source.

It does not activate the FD semantic adapter.

## Authority boundary

Connectivity owns:

- source host
- source port
- database identity
- authentication handshake
- transport ping
- connection close

Connectivity does not own:

- FD movement semantics
- item mapping
- quantity meaning
- unit normalization
- clinic identity
- stock mutation
- backend ingestion

## Verified source facts

The FD schema discovery established:

- database: `FD5_5`
- port: `3306`
- database family: MySQL
- observed server version: `4.1.1a-alpha-nt`

The discovery observed `localhost` on the FD workstation.

That does not prove the database is reachable from another
machine on the clinic LAN.

Therefore the production connectivity config intentionally
does not hard-code a source host.

## Deployment rule

Do not require the connector to run on the legacy
patient-care workstation.

Preferred production shape:

FD database host
        |
clinic LAN
        |
supported Windows connector gateway
        |
Clinic Smart Staff backend

When a safe maintenance window is available, determine whether
the FD MySQL service is reachable read-only from the supported
gateway.

## Secret rule

Database password must be supplied through:

`CLINIC_SOURCE_DB_PASSWORD`

It must not be committed into JSON or installer files.

## Test command

After a real connection config has been created on the
supported connector host:

node bin/test-source-connectivity.js <config-path>

Success means only:

- TCP/MySQL connection/authentication succeeded
- optional MySQL ping succeeded

It does not mean FD inventory semantics have been verified.
