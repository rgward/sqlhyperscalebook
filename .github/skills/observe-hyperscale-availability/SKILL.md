---
name: observe-hyperscale-availability
description: >-
  Run the Chapter 7 Azure SQL Hyperscale availability investigation: establish
  Resource Health and relevant Service Health evidence, execute the read-only
  wardgeneral replica query with the new sqlcmd command, query the previous 24
  hours of Azure Monitor availability and connection metrics, interpret
  Hyperscale topology and synchronization state, identify the current
  connection, and optionally compare the evidence with Microsoft Copilot in
  Azure. USE WHEN the
  reader says "Run the Chapter 7 availability investigation for wardgeneral"
  (the book's prompt), "run the Chapter 7 availability example", "observe Hyperscale
  availability", "check wardgeneral replica health", "show replica
  synchronization", "inspect Hyperscale HA", or "ask Copilot about database
  availability". Do NOT fail over, change replicas, or treat Copilot as the
  source of record.
---

# Observe Hyperscale availability — Chapter 7

Guide the reader through
`examples/ch07-observability/availability/README.md`. Read that README before
running anything; it is the reader-facing source of truth and must remain
capability-equivalent to this skill.

## Scope and safety

This workflow reads Azure health surfaces and SQL replica state. It changes
nothing.

- Never trigger a failover or change replica configuration to manufacture an
  availability event.
- Never equate Resource Health with replica synchronization.
- Never invent a continuous-priming status. The SQL surfaces used here do not
  expose one directly.
- Microsoft Copilot in Azure is optional and is not authoritative.
- Chapter 9 owns resiliency design, failover mechanics, and corrective action.

## Configuration

Use `WardGeneral__Server` and `WardGeneral__Database`, including values loaded
from `examples/ch04-first-app/ch04.env` when present. Do not discover or guess a
logical-server name.

The launcher verifies the executable with `sqlcmd --version` and requires the
new Go-based implementation, which prints a `Version: v1...` line. The command
is always `sqlcmd`. Never request a password or place one on a command line.

## Exact workflow

1. Read `examples/ch07-observability/availability/README.md`.
2. Run the launcher, which loads the Chapter 4 environment when present,
  resolves and prints the Azure subscription, exact database resource ID,
  region code, and Azure region display name, then validates the new sqlcmd
  and executes the SQL:

   ```powershell
  ./examples/ch07-observability/availability/run-availability.ps1
   ```

3. Read `resource-health.json` from the launcher's printed evidence directory.
  Record availability state, summary, occurred time, and reported time. If it
  says unavailable, report that with the error; do not substitute a guess.
4. Read `service-health.json` from the same directory. The launcher already
  filtered the subscription's last-30-day events to those whose impacted
  service is `Azure SQL Database` **and** whose impacted regions include the
  database's own region display name. If the Azure MCP Server is available you
  may cross-check with its Resource Health tools, but the files are the source.
5. Report the derived region and the number of matching Service Health events.
  Do not include events for similarly named or unrelated regions.
6. Report the Hyperscale replica roles, server/database endpoints, locality,
   parent relationships, and replica IDs.
7. Report synchronization, suspension, lag, and database-state fields exactly
   as returned. Explain null remote-replica fields without calling them failed.
8. Report the current connection's server, updateability, database status, and
   UTC sample time.
9. Read `azure-monitor-availability.json` from the launcher's printed evidence
  directory. Report the exact 24-hour UTC window and all six metrics:
  `availability`, `connection_successful`, `connection_failed`,
  `connection_failed_user_error`, `blocked_by_firewall`, and
  `replication_lag_seconds`.
10. For Availability, report the minimum and whether all one-minute buckets
  were 100%. For connection and firewall metrics, report totals. For
  replication lag, report Average and Maximum when values exist. An empty
  series is unavailable, not zero.
11. State that Availability is connection-based historical evidence and that
  continuous priming has no direct status column in the replica DMVs.
12. If Copilot access exists, provide the README's exact availability prompt and
   have the reader compare its claims with the preserved portal and SQL
   evidence. Do not represent the agent as having run the portal prompt itself.

## Required chat report

Always finish the run with one structured assessment in the chat window. Do not
write a per-run Markdown report. Use the current run's evidence, not the live
validation values in the README, and use this exact section order:

1. **Chapter 7 availability investigation complete** — assessed database,
   exact resource ID, dynamically derived region, and run time.
2. **Authoritative baseline** — a table with Source, UTC timestamp or window,
   Observed evidence, and Conclusion. Include Resource Health, exact-region
   Service Health, Azure Monitor, replica topology/state, and current
   connection.
3. **Azure Monitor — previous 24 hours** — a table with Metric, Aggregation,
   Returned samples, and Result for all six metrics. Distinguish numeric zero
   from **No values returned**.
4. **Replica detail** — a table with Role, Endpoint, Locality, Parent,
   Synchronization state, Suspension state, and Lag exactly as returned.
5. **Conclusion and limitations** — distinguish historical connection-based
   evidence from point-in-time replica evidence. State every unavailable or
   inconclusive field and the direct continuous-priming-status limitation.
6. **Microsoft Copilot in Azure prompt** — reproduce the README prompt exactly
   in a fenced text block and tell the reader to run it separately.

Do not claim to have run Microsoft Copilot in Azure. When the reader supplies
its response, append a separate comparison table with these columns:

| Claim | Authoritative source | Chapter 7 baseline | Copilot response | Verdict |
| --- | --- | --- | --- | --- |

Compare at least: current Resource Health, exact-region Service Health events,
24-hour Availability, system-error connection failures, user-error/firewall
evidence, replica topology, synchronization/lag, current connection, and the
continuous-priming limitation. Verdict is **Confirmed**, **Contradicted**,
**Missed**, or **Inconclusive**. Copilot never overrides the deterministic
baseline.

## Interpretation rules

- `sys.dm_hs_database_replicas` is the Hyperscale topology source.
- `sys.dm_database_replica_states` is synchronization evidence visible from
  the current connection; not every field is populated for every row.
- `SYNCHRONIZED` is a point-in-time state, not a guarantee of future health.
- A named replica is a workload-isolation replica, not an HA failover target.
- Resource Health and Service Health are platform evidence; SQL DMVs are
  database and replica evidence. Preserve their timestamps and correlate them.
- Azure Monitor Availability is a one-minute connection-based metric. No
  connection attempts, user errors, and firewall blocks do not reduce it; it
  reaches 0% only when all attempts in a minute fail from system errors.
- `replication_lag_seconds` is preview, available on the primary, and historical
  metric evidence; it does not replace the replica synchronization DMVs.
- Never infer or reuse a region from the resource-group name, server name,
  previous run, or book example. Derive it from `az sql db show` every run.

## Files this skill uses

| File | Role |
|---|---|
| `examples/ch07-observability/availability/README.md` | Reader runbook, portal sequence, Copilot comparison, and boundaries |
| `examples/ch07-observability/availability/run-availability.ps1` | Azure scope and region resolution, configuration validation, new sqlcmd launcher, and 24-hour Azure Monitor metric collection |
| `examples/ch07-observability/availability/availability.sql` | Read-only Hyperscale topology and synchronization evidence |
