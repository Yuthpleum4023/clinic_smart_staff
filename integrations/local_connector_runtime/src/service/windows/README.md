# Windows Service Shell

The production connector is intended to run on a supported Windows gateway or server near the clinic source system.

## Important legacy-host rule

Do not require installation on an unsupported legacy patient-care workstation.

For legacy systems such as an old Windows host, prefer a supported Windows 10/11/Server gateway on the same clinic LAN when the source database can be reached read-only over the network.

## Service contract

The service host must:

- start `bin/connector.js`
- provide `CONNECTOR_CONFIG_PATH`
- provide connector/database secrets through protected environment or service-secret configuration
- restart on unexpected process exit
- stop gracefully
- never expose source database ports to the public internet

Actual Windows service registration/installer packaging is a later packaging checkpoint.
