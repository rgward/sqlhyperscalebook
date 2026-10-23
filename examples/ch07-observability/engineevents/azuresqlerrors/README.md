# Chapter 7 — Retain Azure SQL Errors

This workflow routes Azure SQL Database `Errors` resource logs to a dedicated
Log Analytics workspace, generates one controlled error, queries the
resource-specific `AzureSQLErrors` table, and removes only the resources this
example owns.

> **New here?** Read the [engine-events README](../README.md) first. Configure
> the server and database in
> [`../../../ch04-first-app/ch04.env`](../../../ch04-first-app/ch04.env.template).

## Cost and safety

Setup enables billable Log Analytics ingestion and retention. Use it only in a
learning environment. Run setup and teardown with `-WhatIf` first. Workspace
deletion is recoverable unless `-PermanentlyDelete` is explicitly supplied.

## Workflow

> **Start here first.** Azure takes anything from a few minutes to a few hours
> to start sending a new database's errors to Log Analytics, and an error
> raised before then is never retained. Run step 1 at the **start** of your
> Chapter 7 session, before the performance and availability examples, so the
> route is ready by the time you get here.

1. Preview and approve setup:

   ```powershell
   ./examples/ch07-observability/engineevents/azuresqlerrors/setup-azuresqlerrors.ps1 -WhatIf
   ./examples/ch07-observability/engineevents/azuresqlerrors/setup-azuresqlerrors.ps1
   ```

2. Raise the test error and wait for it to arrive:

   ```powershell
   ./examples/ch07-observability/engineevents/azuresqlerrors/azuresqlerrors.ps1 -Wait
   ```

   `-Wait` runs `generate-azuresqlerror.sql` (error 50001, marker
   `CH07_ENGINEEVENTS_AZURESQLERRORS_TEST`), queries `AzureSQLErrors`, and
   repeats every 5 minutes until the error appears, for up to 3 hours. It then
   shows every retained error for the database. The test error is intentional
   and changes no data or schema. Leave it running; most of the time it
   finishes within 30 minutes.

   To raise an error yourself instead, run either SQL file once against
   `wardgeneral`, then query (step 3). A nonzero client exit is expected:

   ```text
   azuresqlerrors/generate-azuresqlerror.sql       error 50001
   azuresqlerrors/generate-object-not-found.sql    error 208 (misspelled clinical.Observaton)
   ```

3. Query retained rows at any time:

   ```powershell
   ./examples/ch07-observability/engineevents/azuresqlerrors/azuresqlerrors.ps1
   ```

   Delivery is asynchronous, and the telemetry path can throttle. No rows does
   not prove that the application saw no errors. If you raised an error
   yourself and it doesn't appear, it may have been raised before Azure started
   sending; run step 2 (`-Wait`).

4. Preview and approve teardown when the retained evidence is no longer needed:

   ```powershell
   ./examples/ch07-observability/engineevents/azuresqlerrors/teardown-azuresqlerrors.ps1 -WhatIf
   ./examples/ch07-observability/engineevents/azuresqlerrors/teardown-azuresqlerrors.ps1
   ```

## Files

| File | Purpose |
| --- | --- |
| `setup-azuresqlerrors.ps1` | Creates the tagged workspace and resource-specific `Errors` route. |
| `generate-azuresqlerror.sql` | Raises controlled user error 50001. |
| `generate-object-not-found.sql` | Raises system error 208 through a misspelled table name. |
| `azuresqlerrors.ps1` | Queries retained `AzureSQLErrors` rows read-only. With `-Wait`, raises the test error and repeats until it arrives. |
| `teardown-azuresqlerrors.ps1` | Removes the owned diagnostic setting and workspace with safeguards. |

## Source

- [Microsoft Learn — AzureSQLErrors](https://learn.microsoft.com/azure/azure-monitor/reference/tables/azuresqlerrors), accessed 2026-09-01
