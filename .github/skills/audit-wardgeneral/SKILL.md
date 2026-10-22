---
name: audit-wardgeneral
description: >-
  Capture and investigate Chapter 8 Ward General application activity with
  Azure SQL Database auditing and Log Analytics. USE WHEN the reader says
  "start the Ward General audit", "I opened a patient chart. Find my audit
  activity." (both are the book's prompts), "audit Ward General", "start SQL auditing",
  "audit my app activity", "find my Ward General audit events", "show who
  opened a patient chart", "query the SQL audit", "what did the app access",
  or "tear down the Chapter 8 audit".
  Runs a two-turn workflow: enable the guarded audit destination and record a
  UTC start time, let the reader use the app, then query and interpret that
  fixed interval. Do not use for Azure Activity Log, Extended Events,
  AzureSQLErrors, ledger verification, or Defender alerts.
---

# Audit Ward General — Chapter 8

Read `examples/ch08-security/auditing/README.md` and
`examples/ch08-security/README.md` before running anything. They are the
reader-facing source of truth and must remain capability-equivalent to this
skill.

## Scope and safety

This optional companion investigation configures Azure SQL Database auditing at
the logical-server level with a dedicated Log Analytics workspace, captures a
bounded interval of synthetic Ward General activity, and queries
`SQLSecurityAuditEvents`. It does not change the Ward General schema or data.

The workspace has billable ingestion and retention. Before setup, run
`examples/ch08-security/auditing/setup-auditing.ps1 -WhatIf`, show the exact
plan, and obtain explicit approval. After approval, run the setup with
`-Confirm:$false`; do not make the reader approve the same action again in the
PowerShell prompt.

Never replace or combine with an existing audit destination. Trust the setup
script's refusal if another policy exists. Never ask for or place a SQL
password on a command line. The scripts use the existing
`examples/ch04-first-app/ch04.env` configuration and Azure sign-in.

All Ward General data is synthetic. Even so, report only the bounded evidence
needed for the investigation; do not reproduce patient-chart contents from an
audited statement.

## Two-turn workflow

### Turn 1 — Start capture

When the reader asks to start or run the Ward General audit investigation:

1. Run `examples/ch08-security/auditing/setup-auditing.ps1 -WhatIf`.
2. Explain that setup creates a tagged Log Analytics workspace with 30-day
   retention and changes the logical server audit policy. Obtain explicit
   approval.
3. Run `examples/ch08-security/auditing/setup-auditing.ps1 -Confirm:$false`.
4. Require setup to report exactly one enabled `SQLSecurityAuditEvents` route
   on the logical server's `master` database to the tagged workspace.
5. Capture the `AuditStartUtc` value printed by the script. Keep that UTC value
   for the second turn; do not substitute a later time.
6. Stop after auditing is ready. Do not start, restart, or otherwise manage
   Ward General from this skill.
7. Tell the reader to start Ward General with the book's prompt, **`Run the
   Chapter 8 RLS app demo`**, open the unit board, and then open one patient
   chart. End with the exact continuation prompt:
   `I opened a patient chart. Find my audit activity.`

### Turn 2 — Find the activity

When the reader says the app activity is complete or asks to find the audit
events:

1. Capture `AuditEndUtc` immediately.
2. Run `examples/ch08-security/auditing/query-audit.ps1` from five seconds
   before the saved `AuditStartUtc` through five seconds after `AuditEndUtc`.
   The small guard accounts for client/server clock and audit-event timing;
   filtering on `wardgeneral-app` keeps the interval discriminating. Show the
   raw bounded result before drawing conclusions.
3. Find successful rows where `Application` is `wardgeneral-app`. Identify the
   unit-board statement against `ops.vBedCensus` and a chart request involving
   `clinical.GetPatientChart` or `clinical.GetPatientChartByBed`. Report what
   the returned evidence actually contains; do not assume whether an operation
   appears as an RPC, batch, or expanded statement.
4. When Row-Level Security is enabled, find the batch containing
   `sys.sp_set_session_context` and correlate it by `SessionId` with the
   following unit-board or chart query. For the `Microsoft.Data.SqlClient` call
   shape used by Ward General, the `RPC COMPLETED` statement expands the
   `sp_executesql` call and includes the bound `ProviderId` and `Role` values.
   Report those measured values, while noting that AzureDiagnostics does not
   expose a separate `session_context` column.
5. Report event time, session ID, server and database principal, action,
   success, client address, application name, and the minimum statement text
   needed to identify the operation.
6. Explain that the database principal is the authenticated application
   identity, not the Chapter 8 simulated **Viewing as** provider carried in
   `SESSION_CONTEXT`.

Audit delivery is asynchronous. Query the fixed interval once. If no matching
rows have arrived, do not widen the interval, poll, or generate replacement
activity. Preserve both UTC bounds and tell the reader to invoke the same
continuation prompt after a few minutes; rerun the identical interval then.

Exception: a destination created in this workflow can take up to 90 minutes to
start receiving events, and activity before then is never retained. If the
script reports *No audit records have reached workspace … yet* and setup was
less than about 90 minutes ago, explain this. Rerunning the same interval may
never return the activity. Offer to record a new UTC start time and have the
reader open a chart again; don't do it without their agreement.

If the saved start time is unavailable, say so. Use the script's default
previous-30-minute window only with the reader's approval, because it is less
discriminating than the intended fixed interval.

## Session-context probe without Ward General

When the reader asks to test whether auditing exposes bound `ProviderId` and
`Role` values without running the web app:

1. Require auditing to be enabled through the guarded setup workflow above.
2. Run `examples/ch08-security/auditing/probe-session-context.ps1`. This finite
   console probe uses .NET 10, `Microsoft.Data.SqlClient` 6.0.1,
   `ActiveDirectoryDefault`, and the same parameterized setter batch as Ward
   General. It uses application name `wardgeneral-audit-probe`, reads no
   patient data, and changes no schema or table data.
3. Preserve its `ProbeStartUtc`, `ProbeEndUtc`, `AuditQueryStartUtc`,
   `AuditQueryEndUtc`, `SessionId`, `ExpectedProviderId`, and unique
   `ExpectedRole` output. Require
   `ProbeResult=PASS`, which proves the bound values were set and read back on
   the same connection. The probe takes both UTC boundaries from
   `SYSUTCDATETIME()` on Azure SQL and emits audit-query boundaries with a
   fixed five-second guard for audit-event timing.
4. Query the emitted audit interval with `query-audit.ps1 -StartUtc
   <AuditQueryStartUtc> -EndUtc <AuditQueryEndUtc> -Application
   wardgeneral-audit-probe -Detailed`.
5. Inspect `Statement` and `AdditionalInformation` in the raw output. Report
   separately whether the setter call appears, whether it shares the probe's
   session ID, and whether either field contains each expected value.
6. Expect the `RPC COMPLETED` statement to contain both bound values for this
   driver and call shape, as verified live on 2026-09-05. Treat a missing value
   as a regression or changed audit representation. The documented Azure SQL
   Database `AzureDiagnostics` mapping does not include a separate
   `session_context` column.

## Teardown

Do not tear down automatically after reporting the evidence. When the reader
asks to remove the audit resources:

1. Run `examples/ch08-security/auditing/teardown-auditing.ps1 -WhatIf` and show
   the exact plan.
2. Obtain explicit approval because teardown disables the audit policy and
   deletes the tagged workspace.
3. Run `examples/ch08-security/auditing/teardown-auditing.ps1 -Confirm:$false`.

The teardown script must refuse to alter a combined or unrelated audit policy
and must refuse to delete an unowned workspace. It discovers the generated
`SQLSecurityAuditEvents_*` diagnostic setting on `master`, refuses to remove it
if it carries any other enabled log or metric category, disables auditing,
deletes the audit-only route if Azure leaves it behind, and then deletes the
tagged workspace.

## Required report

For setup, report the server, database, workspace, enabled audit action groups,
generated route, retention, and `AuditStartUtc`. For investigation, report the fixed UTC window,
the matching app evidence, whether unit-board and patient-chart activity were
both proved, whether a context-setter batch was correlated on the same session,
and any delivery limitation. For teardown, report the audit policy and owned
workspace removed.

**Always end a setup or investigation report with the cost reminder** (never
tear down on your own):

> Auditing is still on for every database on `<server>`, sending to
> `<workspace>` (billable ingestion, 30-day retention). When you're finished,
> say **"Tear down the Chapter 8 audit."**

## Files

| File | Role |
| --- | --- |
| `examples/ch08-security/README.md` | Chapter example map and scope boundary |
| `examples/ch08-security/prompts.md` | Canonical VS Code Chat skill prompts |
| `examples/ch08-security/auditing/README.md` | Reader-facing audit workflow |
| `examples/ch08-security/auditing/setup-auditing.ps1` | Guarded workspace and server-audit setup |
| `examples/ch08-security/auditing/probe-session-context.ps1` | Finite same-driver session-context probe |
| `examples/ch08-security/auditing/session-context-probe/` | .NET 10 probe source |
| `examples/ch08-security/auditing/query-audit.kql` | Bounded `SQLSecurityAuditEvents` query |
| `examples/ch08-security/auditing/query-audit.ps1` | Read-only Log Analytics query driver |
| `examples/ch08-security/auditing/teardown-auditing.ps1` | Guarded audit-policy and workspace teardown |