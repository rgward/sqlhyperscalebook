---
name: observe-hyperscale-performance
description: >-
  Run the Chapter 7 Ward General observability investigation: establish an idle
  Azure Monitor baseline, remove clean buffer-pool pages, launch exactly three
  concurrent read-only sqlcmd scans of clinical.Observation, measure the RBPEX
  and page-server read split, and correlate the UTC interval with
  sys.dm_db_resource_stats, sys.dm_io_virtual_file_stats, Query Store, and the
  ValueNumeric missing-index recommendation stored in the plan.
  USE WHEN the reader says any of: "run the Chapter 7
  performance demo", "show the Azure Monitor CPU spike", "run concurrent scans",
  "observe page server reads", "test a cold Hyperscale cache", "why did CPU
  spike", "drill into Hyperscale performance", "find the expensive Ward General
  query", or "compare cold and warm reads". Read-only but intentionally
  resource-intensive. Do NOT scale, fail over, create replicas, clear RBPEX,
  create indexes, tune the query, or introduce sqlsim.
---

# Observe Hyperscale performance — Chapter 7

Guide the reader through the exact outside-in performance investigation in
`examples/ch07-observability/perf/README.md`. Read that README before running
anything; it is the reader-facing source of truth and must remain capability-
equivalent to this skill.

## Scope and safety

This workflow removes clean pages from the buffer pool and then runs exactly
three concurrent, read-only scans of the roughly 108-million-row
`clinical.Observation` table. It changes no data, but both the buffer-pool reset
and scans can affect other users.

- An explicit request to **run** the Chapter 7 demo or concurrent scans is
  consent to run the workload.
- If the reader asks only how it works, explain it without executing it.
- If intent to run is ambiguous, confirm before launching the scans. Do not ask
  for a second approval after an explicit request to run the demo.
- Never run this against production. The explicit demo request authorizes its
  documented `DBCC DROPCLEANBUFFERS` step against the lab database.
- Never issue `CHECKPOINT`, clear RBPEX, scale, fail over, create a replica, or
  change service objectives to manufacture page-server reads.
- Never create the recommended index. Chapter 10 owns remediation.
- Do not offer to create, verify, or drop an index as part of this workflow.
  Conclude that the investigation found the issue: the `ValueNumeric` predicate
  has no supporting access path, causing the large scan and CPU spike. State
  that Chapter 10 evaluates possible solutions and their performance, storage,
  and write-cost tradeoffs without treating the raw recommendation as a
  mandate.
- Never substitute sqlsim. This chapter intentionally uses three new sqlcmd
  processes so the concurrency is visible and self-contained.

## Configuration

The launcher accepts `-Server` and `-Database`, then falls back to
`WardGeneral__Server` and `WardGeneral__Database`. It also loads the existing
`examples/ch04-first-app/ch04.env` when present.

Do not discover or guess a logical-server name. If no server is configured,
tell the reader to fill in `examples/ch04-first-app/ch04.env`, set
`WardGeneral__Server`, or pass `-Server` explicitly.

The launcher requires the new Go-based sqlcmd and rejects the legacy ODBC binary. If it is
missing, use the README's installation command. Never request a password or put
one on a command line; the new sqlcmd's `-G` uses the reader's passwordless identity.

## Controlled cache assumption

Assume the observation pages are clean. The orchestrator snapshots RBPEX and
page-server virtual-file counters, runs `DBCC DROPCLEANBUFFERS` without a prior
`CHECKPOINT`, executes the scans, and snapshots both sets again. Describe this
as removing clean buffer-pool pages, never as clearing RBPEX or guaranteeing a
cold Hyperscale compute cache.

Report whatever the deltas prove: RBPEX reads, page-server reads, both, or
neither. Do not promise page-server reads. A zero page-server delta with a
nonzero RBPEX delta means RBPEX served the removed pages.

Use these exact evidence locations:

- `run-summary.json` → `RbpexVirtualFileDelta` for local SSD cache reads,
  bytes, and read-stall milliseconds.
- `run-summary.json` → `PageServerVirtualFileDelta` for page-server reads,
  bytes, and read-stall milliseconds.
- `session-*.txt` → statement-level `page server reads` and `page server
  read-ahead reads` from `STATISTICS IO`.
- Azure Monitor Data IO percentage → local SSD utilization pressure only; it
  neither identifies RBPEX reads nor counts page-server reads.

Interpret all four combinations explicitly: RBPEX only, page server only,
both, or neither. If neither delta moves, do not infer a source; state that the
lower-tier path was not established by this run.

Do not route this callback to Chapter 9; that chapter owns HA and failover.
Chapter 10 owns named-replica read scale and can create a fresh named replica
for a separate first-touch/warm-repeat investigation. Named replicas have
independent compute caches and do not benefit from continuous priming. The
Chapter 7 workflow itself must not create a replica.

## Exact workflow

1. An explicit request such as "Run the Chapter 7 performance demo for
  wardgeneral" authorizes the bounded workload. Do not request another
  approval.
2. From the repository root, run exactly one reader-facing command:

   ```powershell
  ./examples/ch07-observability/perf/run-performance-demo.ps1
   ```

3. Do not separately run the launcher, drill-down SQL, or Azure Monitor query;
  the orchestrator owns the complete sequence.
4. Read `run-summary.json`, `performance-drilldown.txt`, and
  `azure-monitor-metrics.json` from the printed evidence directory.
5. Report all three sessions' query CPU, elapsed time, logical
   reads, page-server reads, and page-server read-ahead.
6. Report the RBPEX and page-server virtual-file deltas. Interpret per-session
  page-server evidence as the sum of synchronous and read-ahead pages. Do not
  call either value `RBIO_*` and do not infer Azure Storage reads behind the
  page server.
7. Correlate Azure Monitor Average and Maximum values with the 15-second resource
  samples, the before-and-after RBPEX and page-server virtual-file deltas, Query
  Store execution count/CPU/duration/logical reads, and the `ValueNumeric`
  missing-index recommendation extracted from the stored Query Store plan.
8. If Azure Monitor has not published the workload points yet, report that lag
  and preserve the UTC interval. Do not rerun the workload blindly. Azure
  Monitor can label the aggregate at the following minute boundary, so include
  at least one minute after the workload when checking the preserved interval.
9. Report repeatability precisely: the evidence chain and query shape are
  repeatable, but exact CPU, duration, publication delay, and the RBPEX/page-
  server split are not deterministic. Promise a visible correlated spike and
  measured lower-tier reads, not a particular percentage or source split.
10. Stop at diagnosis. Hand the preserved evidence to Chapter 10 for tuning.

## Required final report

After the orchestrator completes, return one self-contained report to the
reader. Do not merely list evidence-file paths. Use the measured values from
`run-summary.json`, `performance-drilldown.txt`, and
`azure-monitor-metrics.json`; never copy the validation numbers from the README
as if they were the current run.

Use this exact section order:

1. **Chapter 7 performance investigation complete** — state success or the
  precise failure and give the UTC investigation window.
2. **Session results** — a table with Session, CPU time, Elapsed time, Logical
  reads, Page-server reads, and Page-server read-ahead.
3. **Resource pressure** — report the peak `sys.dm_db_resource_stats` CPU, Data
  IO, and Log IO samples, followed by Azure Monitor Average and Maximum values
  for the corresponding published minute.
4. **Hyperscale read path** — report RBPEX reads/bytes/stall and page-server
  reads/bytes/stall, then classify the outcome as RBPEX only, page server only,
  Mixed, or Neither. Explain that Azure Monitor Data IO measures local SSD
  pressure and does not count page-server reads.
5. **Query Store attribution** — report executions, total CPU, total duration,
  and total logical reads for the marked statement.
6. **Stored-plan recommendation** — report table, column usage, column names,
  and estimated impact from the missing-index element in the Query Store plan.
7. **Diagnosis** — state that the unsupported `ValueNumeric` access path caused
  the large scan and observed pressure. Stop at diagnosis and point solution
  evaluation to Chapter 10 without recommending or creating an index.

Round displayed byte values to GB while retaining raw counts when useful. State
that RBPEX and page-server read counts are not directly comparable as physical
I/O operations. If Azure Monitor has not published the workload minute, say
**not yet published**, preserve the UTC interval, and do not substitute zeros
or rerun the workload. End with the evidence-directory path so the reader can
inspect the raw files.

## Interpretation rules

- A nonzero `PageServerReads` or `PageServerReadAhead` value means that session
  crossed the compute-cache boundary to a page server.
- A nonzero RBPEX virtual-file delta means the local SSD cache served pages.
- Zero page-server counters do not by themselves identify the source; use the
  RBPEX delta. Report both measured paths, including a mixed result.
- Azure Monitor **Data IO percentage** is a utilization percentage, not a
  page-server-read counter.
- In Metrics Explorer use **CPU percentage**, one-minute granularity, and
  **Maximum**. Average or automatic granularity can dilute a short spike.
- `PAGEIOLATCH_*` might remain flat when asynchronous read-ahead hides the wait.
- `RBIO_*` identifies log-governance back-pressure from downstream consumers;
  it does not count remote reads.
- Query Store and `STATISTICS IO` attribute work to the statement. File-level
  virtual-file counters are broader and can include concurrent activity.
- The Query Store plan's missing-index recommendation is optimizer evidence,
  not an order to create an index.

## Files this skill uses

| File | Role |
|---|---|
| `examples/ch07-observability/perf/README.md` | Reader runbook and exact investigation sequence |
| `examples/ch07-observability/perf/run-performance-demo.ps1` | Single reader-facing orchestrator for the complete investigation |
| `examples/ch07-observability/perf/observe-scan.sql` | Marked, read-only scan with SQL I/O and timing statistics |
| `examples/ch07-observability/perf/run-concurrent-scans.ps1` | Three-session launcher and evidence summary |
| `examples/ch07-observability/perf/performance-drilldown.sql` | Resource-stat and Query Store correlation, including the missing-index recommendation stored in the plan |