---
name: scale-wardgeneral-compute
description: 'Run and analyze Chapter 10 Demo 1, the Ward General compute-scaling workload at 8, 16, and 40 vCores. USE WHEN the reader says "Run Chapter 10 Demo 1 and preview the 8 → 16 → 40 vCore progression" (the book''s prompt), "run the Chapter 10 Stage 1 baseline", "run the 8-vCore baseline", "run Demo 1", "scale Ward General compute", "run the 8 to 16 to 40 demo", "test Ward General with sqlsim", or "measure compute scaling under load". Owns preflight, SQLSIM path prompting, the read/write workload, laptop-network controls, server and Query Store evidence, and preview-first approved scaling. Do not grow the database, move to Premium-series, tune indexes, or scale named replicas.'
---

# Scale Ward General compute

Run Chapter 10 Demo 1 from
`examples/ch10-performance/01-scale-compute/README.md`. That README is the
reader-facing source of truth.

## Boundaries

- Reuse the existing `wardgeneral` database and Chapter 2 procedure contract.
- The workload is read/write and appends synthetic vitals, medication orders,
  lab JSON, and notes. State that before running it.
- Load the server and database from `examples/ch04-first-app/ch04.env`.
- Use Azure CLI access-token authentication. Never request a database password.
- Never use terminal history to infer current state; run the fresh preflight.
- Do not scale unless the reader explicitly approves the displayed billable
  changes.
- Never clean between the 8-, 16-, and 40-vCore phases. Retain generated rows
   when continuing to Demo 2.
- Keep every run under the demo's gitignored `results/runs/<UTC-run-id>/`
   directory. Do not redirect canonical run evidence to `_scratch`.
- For a deliberate reset, run preflight with `-ResetDemoData` first and present
   exact counts. Run again with `-ApproveCleanup` only after explicit approval.
   Cleanup deletes all marked Demo 1 rows across prior runs, never unmarked rows.
- This demo ends at `HS_Gen5_40`. It never scales down or moves to Premium.

## Baseline-only prompt

For "run the 8-vCore baseline", do exactly this:

1. Run `preflight.ps1`. If `SQLSIM` is absent or invalid, allow its prompt for
   the full local path to the extracted `sqlsim.exe`.
2. Confirm `HS_Gen5_8`, token authentication, firewall/network connectivity,
   ODBC 18, Query Store, five procedures, and encounter data.
3. Capture `network-probe.ps1` and `capture-server.ps1` before the workload.
4. Run `run-workload.ps1 -WorkloadPath workload-8.json` once.
5. Capture the same network and server evidence after the workload.
6. Report sqlsim throughput/errors/latency, Query Store duration and CPU,
   resource pressure, waits, RBPEX, and network-control drift.
7. Stop. Do not invoke a scale command.

## Full Demo 1

1. Run `run-demo.ps1` without `-ApproveScaling`. It runs preflight and previews
   `HS_Gen5_8 → HS_Gen5_16 → HS_Gen5_40` without changing Azure.
2. Present both changes and obtain explicit approval.
3. Run `run-demo.ps1 -ApproveScaling` only after approval. The resource group
   resolves from `RG` (shell or `ch04.env`) and defaults to `rg-collierhealth`;
   pass `-ResourceGroup` only if the reader names a different one.
4. The script runs 100, 200, and 400 workload threads respectively, each for 90
   seconds, and brackets every phase with network and server evidence.
5. Stop at the first failed workload or scale. Report the actual SLO and do not
   skip ahead.

When the reader asks for a clean full progression, preview with
`preflight.ps1 -ResetDemoData`, obtain separate cleanup approval, then invoke
`run-demo.ps1` with `-ResetDemoData -ApproveCleanup -ApproveScaling`. Do not
infer cleanup approval from scaling approval.

## Interpretation

- sqlsim elapsed time is the laptop-to-database experience.
- Query Store duration/CPU and resource/wait/cache evidence support the
  database-side scaling claim.
- `GetPatientChartByBed` is excluded after live calibration exposed it as an
   independent tuning problem. Do not reintroduce it to make the workload look
   broader; route that finding to Demo 3.
- If the `SELECT 1` control changes by more than 25 percent, do not compare that
  phase's laptop latency; repeat it under a stable path.
- Success means user count doubles from 100 to 200 to 400 while service quality
  remains controlled. Higher throughput alone is not enough.
- Do not add `-querystats` to the sustained workload. Use Query Store and the
   separate server snapshots for database-side timing and resource evidence.

## Reset compute for a repeat — or to stop the cost

`scale-compute.ps1` supports scale-up and scale-down. To repeat Demo 1 after it
ends at 40 vCores, or when the reader is done with Chapter 10 and is not going
on to Demo 2, run it first without `-Approve` targeting `HS_Gen5_8`, show the
reader the current and requested SLO, and obtain explicit approval. Then rerun
with `-Approve`. Never hide the reset inside `run-demo.ps1`.

When reporting the Demo 1 result, always state that the database is now at
`HS_Gen5_40` and bills at that size (primary and HA replica) until scaled back,
and point to "Cost and cleanup" in `examples/ch10-performance/README.md`.

## Connection cap
- Do not raise the reader-laptop 40-vCore phase to 800 direct connections. The
   live calibration stalled during client connection establishment before any
   workload executed; that was not an Azure SQL capacity result.
