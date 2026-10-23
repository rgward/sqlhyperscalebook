---
name: observe-hyperscale-engine-events
description: >-
  Run the Chapter 7 Azure SQL Database engine-events example for wardgeneral:
  create or start the bounded database-scoped wardgeneral_health Extended
  Events session, generate one controlled system error, read its ring buffer,
  and report errors, deadlocks, attentions, drops, and truncation. Also guide
  the separate AzureSQLErrors Log Analytics setup, query, and teardown when
  explicitly requested. USE WHEN the reader says "run the Chapter 7 engine
  events demo", "monitor wardgeneral engine health", "start the Ward General
  health session", "show Azure SQL engine errors", "query AzureSQLErrors", or
  "tear down the Chapter 7 logs", "query sys.event_log", or "show database
  connection stats". Do not collect all Extended Events, change
  application data, or provision/delete billable Azure resources without
  explicit approval.
---

# Observe Hyperscale engine events — Chapter 7

Read `examples/ch07-observability/engineevents/README.md` before running
anything. It is the reader-facing source of truth and must remain
capability-equivalent to this skill.

## Default health workflow

An explicit request to run the Chapter 7 engine-events demo authorizes these
database-scoped lab operations:

1. Run `xevent/setup-xevent-health.ps1`. It loads the shared configuration and
  invokes its companion SQL against `wardgeneral` with the new Go-based sqlcmd
  and passwordless `-G` authentication.
2. Run `xevent/test-xevent-health.sql` exactly once. Error 208 and a nonzero
  sqlcmd exit are expected; do not retry it.
3. Run `xevent/read-xevent-health.sql` exactly once.
4. Report session state, ring-buffer event count, dropped count, truncation,
   memory used, and the controlled `error_reported` row.
5. Leave `wardgeneral_health` running. Run
  `xevent/teardown-xevent-health.ps1 -WhatIf` first, and run it without
  `-WhatIf` only when the reader explicitly asks to remove the session and
  approves discarding its ring buffer.

Never run this against production. The session captures system errors at
severity 16 or higher, database deadlock graphs, and client attentions. It uses
a 1 MB / 1,000-event ring buffer and `ALLOW_SINGLE_EVENT_LOSS` to stay bounded.
Do not add batch-completion, statement-completion, lock-acquisition, or all-event
capture to this baseline.

## Interpretation

- `error_reported` answers which qualifying system error reached the database.
- `database_xml_deadlock_report` carries the database-scoped deadlock graph.
- `attention` means cancellation, timeout, or broken connection; it does not by
  itself identify which of those occurred.
- `STARTUP_STATE=ON` starts a fresh session when the database comes online. It
  does not preserve ring-buffer contents across stop, restart, or failover.
- `DroppedCount > 0` means the target lost events under pressure.
- `Truncated = 1` means data was omitted when the ring buffer was materialized
  as XML.
- Use an Azure Blob `event_file` target when evidence must be durable. Do not
  provision that storage path in this Chapter 7 workflow.

## AzureSQLErrors lifecycle

The Log Analytics path is separate because it creates billable Azure resources.
Do not run `azuresqlerrors/setup-azuresqlerrors.ps1` unless the reader explicitly
asks to set up retained Azure SQL errors and acknowledges the cost warning in
the README.

When authorized:

1. Run `azuresqlerrors/setup-azuresqlerrors.ps1 -WhatIf` and show the plan.
2. Run `azuresqlerrors/setup-azuresqlerrors.ps1` only after approval. If the
   reader is starting Chapter 7, suggest doing this first and returning to it
   after the other examples, because the route takes time to start.
3. When a controlled retained event is requested, run
   `azuresqlerrors/azuresqlerrors.ps1 -Wait`. It raises error 50001 with
   `generate-azuresqlerror.sql`, checks `AzureSQLErrors`, and repeats every 5
   minutes until the error arrives (up to 3 hours). Run it in a terminal and
   tell the reader it can take from a few minutes to a few hours.
4. Run `azuresqlerrors/azuresqlerrors.ps1` without `-Wait` to query the
   configured lookback at any other time.
5. Interpret rows using the source-confirmed capture contract below. Distinguish
   no retained rows from proof that the application saw no SQL errors.

Current implementation source inspection on 2026-09-01 established this
capture contract:

- The internal `sqlserver.error_reported` source predicate is severity 16 or
  higher, or error number 3257, 3999, 17803, 701, 802, 8645, 8651, 8657, or
  8902.
- The downstream transformation also requires `is_azure_connection = 1` and
  `database_id > 4`; it has no additional error-number allowlist. A connection
  from a reader's laptop counts as an Azure connection: in testing on
  2026-10-23, errors raised from a laptop over the public endpoint were
  retained, as were errors from inside Azure.
- Rows are category `Errors`, operation `ErrorEvent`, and can carry error
  number, severity, state, message, user-defined flag, query hash, and plan hash.
- Severity 11–15 application errors are generally excluded. The telemetry
  target can throttle, so this is not a lossless audit stream.

Error 50001 from `azuresqlerrors/generate-azuresqlerror.sql` qualifies because `THROW` is
severity 16 and the workflow uses an Azure connection to `wardgeneral`. If it
does not appear, investigate ingestion delay, diagnostic routing, and telemetry
loss; do not infer an undocumented error-number allowlist.

A diagnostic setting starts sending at an unpredictable moment: in testing on
2026-10-23 it ranged from about 1 minute to about 3 hours, longer than the 90
minutes Azure documents, regardless of how the server was created. An error
raised before then is never retained, even after the route starts. So a single
error raised right after setup can be lost for good. Use `-Wait`, which keeps
raising fresh errors until one arrives. Don't report the route as broken unless
`-Wait` times out.

When the reader asks specifically for an object-not-found test, run
`azuresqlerrors/generate-object-not-found.sql` exactly once instead. Its
deliberately misspelled `clinical.Observaton` reference raises system error 208,
severity 16, and changes no data or schema. A nonzero sqlcmd exit is expected.
If the route may not have started yet, say that this error can be lost and
offer `-Wait` afterwards.

Run `azuresqlerrors/teardown-azuresqlerrors.ps1 -WhatIf` first. Delete the
diagnostic setting and workspace only after explicit approval. Recoverable
workspace deletion is the default; permanent deletion requires the reader to
request it explicitly.

## Master-database connection history

When the reader asks for `sys.event_log`, connection history, or database
connection statistics:

1. Connect to the logical server's `master` database, not `wardgeneral`.
2. Use `connections/connection-history.sql` for an ad-hoc query, or run
  `connections/run-connection-history.ps1` to load configuration and invoke
  that SQL file through the new sqlcmd with `-d master -i`.
3. Report that the queries are read-only, include every database visible to the
  caller, and default to the previous 24 hours. Do not add a database filter.
4. State that data typically appears within an hour but can lag by 24 hours,
  retention is at most 30 days, and neither view is lossless.
5. Do not interpret `terminated_connection_count` or
  `throttled_connection_count`; Microsoft documents both as unused.

## Required chat report

Return a self-contained report with:

- Database and UTC sample time.
- Session name, running state, startup state, target size, and event limit.
- Ring-buffer event, drop, truncation, and memory counters.
- A table of captured UTC time, event, session, database, client, user, error,
  severity, state, attention duration, hashes, and SQL text.
- A clear statement that the ring buffer is a volatile current-health window,
  not retained history or a replacement for SQL Server `ERRORLOG`.
- The exact next command for reading or tearing down the session.

For AzureSQLErrors requests, also report workspace, diagnostic setting,
destination schema, lookback, returned rows, and whether ingestion remains
unproven or delayed.

## Files

| File | Role |
| --- | --- |
| `examples/ch07-observability/engineevents/README.md` | Reader workflow, cost warning, and boundaries |
| `examples/ch07-observability/engineevents/xevent/README.md` | Extended Events workflow |
| `examples/ch07-observability/engineevents/xevent/setup-xevent-health.ps1` | Configured, passwordless health-session setup entry point |
| `examples/ch07-observability/engineevents/xevent/setup-xevent-health.sql` | Idempotent bounded health-session definition |
| `examples/ch07-observability/engineevents/xevent/test-xevent-health.sql` | Controlled system error 208 |
| `examples/ch07-observability/engineevents/xevent/read-xevent-health.sql` | Ring-buffer metadata and event reader |
| `examples/ch07-observability/engineevents/xevent/teardown-xevent-health.ps1` | Confirmed cleanup entry point with `-WhatIf` |
| `examples/ch07-observability/engineevents/xevent/teardown-xevent-health.sql` | Health-session cleanup definition |
| `examples/ch07-observability/engineevents/azuresqlerrors/setup-azuresqlerrors.ps1` | Billable retained-error infrastructure setup |
| `examples/ch07-observability/engineevents/azuresqlerrors/generate-azuresqlerror.sql` | Controlled user error 50001 for diagnostic export testing |
| `examples/ch07-observability/engineevents/azuresqlerrors/generate-object-not-found.sql` | Controlled system error 208 for diagnostic export testing |
| `examples/ch07-observability/engineevents/azuresqlerrors/azuresqlerrors.ps1` | Read-only AzureSQLErrors consumer |
| `examples/ch07-observability/engineevents/azuresqlerrors/teardown-azuresqlerrors.ps1` | Guarded diagnostic-setting and workspace cleanup |
| `examples/ch07-observability/engineevents/azuresqlerrors/README.md` | AzureSQLErrors workflow |
| `examples/ch07-observability/engineevents/connections/README.md` | Connection monitoring and troubleshooting workflow |
| `examples/ch07-observability/engineevents/connections/connection-history.sql` | Ad-hoc query for both connection-history views |
| `examples/ch07-observability/engineevents/connections/run-connection-history.ps1` | Configured `master` connection and both connection-history queries |
