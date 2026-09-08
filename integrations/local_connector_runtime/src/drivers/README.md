# Source Drivers

Generic source drivers own only **how to read** from an external clinic program.

Supported foundation:

- MySQL-family structured read-only polling

Future drivers may include:

- Microsoft SQL Server
- PostgreSQL
- SQLite
- REST API
- CSV / file export

## Driver authority

A driver owns:

- source connection
- source read
- cursor/checkpoint-compatible polling
- transport-level cleanup

A driver does **not** own:

- clinic scope
- connector scope
- vendor semantic mapping
- internal StockItem identity
- stock movement
- reprocessing policy

## MySQL read-only invariant

The MySQL driver does not accept arbitrary SQL.

It accepts a structured poll specification:

- schema
- table
- selected columns
- cursor column
- optional tie-breaker column
- limit

The driver constructs a single `SELECT` statement itself and disables multiple statements.

Production deployments should additionally use a database account granted only the minimum `SELECT` privileges required for the integration.
