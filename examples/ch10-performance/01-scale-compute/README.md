# Stage 1 — Scale Compute Under Load

**Owning skill:** `scale-wardgeneral-compute`

Baseline-only prompt: **Run the Chapter 10 Stage 1 8-vCore baseline only.
Capture network and server evidence before and after, analyze the results, and
do not scale.**

Full-demo prompt: **Run Chapter 10 Demo 1 and preview the 8 → 16 → 40 vCore
progression.**

Start with the existing provisioned Standard-series `wardgeneral` database at
`HS_Gen5_8`. Drive the same bounded Chapter 2 stored-procedure workload at 8,
16, and 40 vCores. The database remains on Standard-series throughout, so the
comparison isolates compute size. Stage 2 keeps that 40-vCore Standard-series
configuration while growing the data.

This stage contains:

- `workload-8.json`, `workload-16.json`, and `workload-40.json` — the same real
  stored-procedure mix at 100, 200, and 400 threads for fixed 90-second windows.
- `sql/` — one batch per stored procedure, used by the JSON workload groups.
- `preflight.ps1` + `preflight.sql` — prompt for `sqlsim.exe` when `SQLSIM` is
  missing, then prove every local, Azure control-plane, network, authentication,
  and database prerequisite. Cleanup remains an explicit optional action.
- `cleanup-preview.sql` + `cleanup-apply.sql` — count exact `CH10-SCALE` rows,
  then optionally delete them as one transaction after approval.
- `run-demo.ps1` — owns the complete `8 → 16 → 40` progression, including the
  two approved compute changes and one identical workload interval per size.
- `run-workload.ps1` — reads the required `SQLSIM` path, obtains an Azure SQL
  access token without printing it, and runs the versioned JSON workload.
- `measure.sql` — reports the focused Chapter 7 evidence used in the comparison.
- `network-probe.ps1` — runs 20 lightweight token-auth round trips before and
  after each phase to detect changes in the laptop/network path.
- `capture-server.ps1` — captures DMVs and recent Query Store evidence before
  and after each workload interval.
- `scale-compute.ps1` — previews the current and requested service objectives
  and requires explicit approval before scaling.
- `summarize-run.ps1` — builds `summary.json`, `summary.csv`, and the HTML
  performance report from a completed orchestration run.

The `sql/get-patient-chart-by-bed.sql` calibration query is retained to make
the workload exclusion reproducible. No shipped workload JSON references it;
the live calibration showed that access path overrunning the bounded interval.

The script deliberately leaves the database at `HS_Gen5_40`. Stage 2 grows the
same database without changing that hardware configuration.

## Install sqlsim

Download the Windows release from `https://aka.ms/sqlsimtools`, extract it to a
local folder, and set `SQLSIM` to the full executable path.

```powershell
$env:SQLSIM = 'C:\tools\sqlsim\x64\sqlsim.exe'
```

The setting is process-scoped in that example. Demo 2 runs in a new process and
also needs it, so set it for your user once and open a new terminal:

```powershell
[Environment]::SetEnvironmentVariable('SQLSIM', 'C:\tools\sqlsim\x64\sqlsim.exe', 'User')
```

If `SQLSIM` is missing or invalid, `preflight.ps1` prompts for the full path and
sets it for the current process.

sqlsim also requires ODBC Driver 18 for SQL Server. Stage 1 uses an Azure SQL
access token from the reader's existing `az login`; no database password is
accepted or placed on the command line.

Every sqlsim data-plane call retries an initial transient connection failure up
to three times with a five-second delay. Query errors are not hidden or retried.

## Workload composition

The workload is **not read-only**. It models the application contract already
built in Chapters 2–6:

| Procedure | 8 / 16 / 40 vCore threads | Think time | Effect |
| --- | ---: | ---: | --- |
| `clinical.GetPatientChart` | 90 / 180 / 360 | 500 ms | Read a complete chart by encounter. |
| `clinical.RecordVitals` | 4 / 8 / 16 | 250 ms | Append a synthetic vital. |
| `clinical.PlaceMedicationOrder` | 2 / 4 / 8 | 1,000 ms | Append a synthetic medication order. |
| `clinical.FileLabResult` | 2 / 4 / 8 | 1,500 ms | Append a synthetic CBC JSON result. |
| `clinical.AddClinicalNote` | 2 / 4 / 8 | 1,500 ms | Append a synthetic progress note. |

Ninety percent of allocated threads serve reads at every size; write groups
have longer think times to model less frequent clinical actions. All writes use synthetic data.
Notes and lab JSON carry the `CH10-SCALE` marker. The workload does not admit or
discharge patients because random bed-state transitions would create expected
business conflicts and distort the compute comparison.

`GetPatientChartByBed` is deliberately excluded from the scaling workload. A
live calibration run with 24 concurrent callers averaged 162.3 seconds of
server duration and kept in-flight calls alive long after the 90-second
deadline. That access path is a query-tuning problem, not evidence for compute
scaling, and belongs in future tuning work. `run-workload.ps1` also sets a 60-second query
timeout so a future bad phase stops instead of overrunning indefinitely.

## Run it

The scripts read the server and database from `examples/ch04-first-app/ch04.env`.
The resource group comes from `-ResourceGroup`, then `$env:RG`, then `RG=` in
`ch04.env`, then the Chapter 2 default `rg-collierhealth` — so readers who kept
the default pass nothing.

Run the preflight by itself when preparing the environment:

```powershell
./preflight.ps1
```

It verifies ODBC Driver 18, Azure CLI login, access-token acquisition, Azure
control-plane visibility, token-auth connectivity through the current firewall
  or private-network path, all five procedures, encounter seed data, Query Store,
and the `HS_Gen5_8` starting state. It cannot prove permission to update the
database without attempting a change; the first approved scale is the
management-plane authorization check.

## Reset before a fresh progression

Do not clean between 8, 16, and 40 vCores. Those phases are one progression,
and cleanup would add unrelated writes and change cache state between
measurements. Retain the generated data when continuing into Demo 2.

When deliberately repeating Demo 1 from a clean marker state, preview first:

```powershell
./preflight.ps1 -ResetDemoData
```

The preview changes nothing. After reviewing the counts, approve the atomic
delete explicitly:

```powershell
./preflight.ps1 -ResetDemoData -ApproveCleanup
```

The cleanup deletes **all** exact `CH10-SCALE` rows from all prior Demo 1 runs,
not one selected run. It deletes matching note embeddings before notes, then
labs, medication orders, and observations. It never touches unmarked rows.

The first calibration runs predated exact markers on vitals and medication
orders, so those older rows cannot be safely identified and are intentionally
left in place. Future vitals use a `CH10-SCALE:` unit prefix; future medication
orders use `CH10-SCALE:Acetaminophen`; labs and notes retain their existing
markers.

The live preview on 2026-09-12 found 185 marked notes, 186 marked labs, zero
marked note embeddings, and zero marked observations or medication orders. No
rows were deleted.

Preview the complete progression. This validates that the database starts at
`HS_Gen5_8`, runs the same preflight automatically, and changes nothing:

```powershell
./run-demo.ps1
```

After reviewing both billable changes, authorize the displayed plan:

```powershell
./run-demo.ps1 -ApproveScaling
```

To reset the exact marker rows before the approved full progression, first run
the cleanup preview above and obtain approval, then pass both cleanup switches:

```powershell
./run-demo.ps1 -ResetDemoData -ApproveCleanup -ApproveScaling
```

The approved run performs:

1. Workload at `HS_Gen5_8` with 100 users.
2. Scale to `HS_Gen5_16`, then run 200 users with the same mix.
3. Scale to `HS_Gen5_40`, then run 400 users with the same mix.

The user population doubles at every phase. Compute doubles for the first move
and increases by 2.5 times for the second, leaving deliberate server headroom at
40 vCores.

The sustained workload does not use sqlsim `-querystats`. Enabling
`SET STATISTICS TIME/IO` collection on every execution changes CPU and message
traffic. Server-side evidence comes from Query Store, resource stats, waits,
and RBPEX snapshots captured separately.

The 40-vCore reader workload is capped at 400 direct sqlsim connections. A
live 800-thread attempt from the author's laptop never reached workload
execution because client-side connection establishment did not complete. Do
not present that as a database limit. An Azure-hosted driver can test a larger
user population separately, but the reader-laptop progression must remain
portable and finish reliably.

Every full progression is written beneath
`examples/ch10-performance/01-scale-compute/results/runs/<UTC-run-id>/`. That
run folder contains raw sqlsim output, network controls, server snapshots,
incremental metadata, `summary.json`, `summary.csv`, and
`performance-report.html`. The `results/` directory is gitignored, so local
evidence stays beside the book example without entering the repository.

The report's bottom table shows operations per second for each stored-procedure
workload, calculated from phase-specific Query Store execution-count deltas.
`summary.json` also retains execution counts plus average CPU and duration for
diagnosis.

The book says the report captures throughput, latency, Query Store
CPU/duration, resource pressure, waits, RBPEX, and network drift. The HTML
report draws throughput, client latency, peak CPU, and a phase table with
worker pressure, failures, and network drift. The rest of that evidence is in
the same run folder:

| Evidence | Where to find it |
| --- | --- |
| Query Store CPU and duration per procedure | `summary.json` → `ProcedureServerExecution` (`AverageCpuMs`, `AverageDurationMs`) |
| Resource pressure (CPU, data I/O, log write, workers, sessions) | `summary.json` / `summary.csv` → `Peak*Percent` |
| Waits (`PAGEIOLATCH_SH`, `WRITELOG`, `RBIO_RG_*`) | `summary.json` / `summary.csv` → `*WaitDeltaMs` |
| RBPEX cache hit ratio | `server-<slo>-before.txt` and `server-<slo>-after.txt` (raw `measure.sql` output) |
| Network drift | `network-<slo>-before.json`, `network-<slo>-after.json`, and the report's phase table |

`measure.sql` reads `sys.dm_db_wait_stats`, the database-scoped equivalent of
`sys.dm_os_wait_stats` in Azure SQL Database.

Standalone preflight and workload runs use `results/preflight/` and
`results/standalone/`. If any workload or scale fails, the script stops and
preserves the partial run folder; it does not skip ahead or automatically scale
down.

`run-workload.ps1` and `scale-compute.ps1` remain available for repeating one
interval or one scale independently.

`scale-compute.ps1` is bidirectional. After Demo 1 has left the database at 40
vCores, preview a reset to the required starting SLO:

```powershell
./scale-compute.ps1 -TargetServiceObjective HS_Gen5_8
```

Only after approving that displayed billable change, rerun with `-Approve`.
`run-demo.ps1` itself never scales down automatically.

## Laptop and network latency

sqlsim measures the experience from the computer where it runs. Its elapsed
time therefore includes the laptop, ODBC driver, internet or VPN path, Azure SQL
gateway path, result transfer, and database execution. A faster database cannot
remove a slow or unstable client network, and the chart procedures return
substantial JSON that can expose bandwidth limits.

`run-demo.ps1` brackets every 90-second workload with two controls:

- `network-<slo>-before.json` and `network-<slo>-after.json` contain 20
  lightweight `SELECT 1` round trips over one persistent token-auth connection.
- `server-<slo>-before.txt` and `server-<slo>-after.txt` contain resource stats,
  Hyperscale cache/wait evidence, and recent Query Store duration and CPU for
  the five workload procedures.

The network control is a drift detector, not a bandwidth benchmark. If its
average query latency changes by more than 25% during a phase, the script warns
that laptop latency is contaminated and that phase should be repeated. Keep the
same laptop, location, VPN state, and connection type for all three phases.

Interpret the evidence together:

- Query Store duration improves and sqlsim latency improves: scaling helped the
  server and the end-to-end experience.
- Query Store improves but sqlsim does not: the client/network/result path is
  masking the server improvement.
- CPU or workers stay constrained and neither improves: the database remains
  compute-bound.
- The network control shifts materially: do not compare that phase's laptop
  latency until it is repeated under a stable path.

Canonical book measurements should come from a controlled driver in the same
Azure region as the database. The laptop run remains valuable because it shows
the reader's real end-to-end experience, but server-side Query Store and
resource evidence support the compute-scaling claim.

Source: [Microsoft Learn — Azure SQL Database resource limits](https://learn.microsoft.com/azure/azure-sql/database/resource-limits-vcore-single-databases), accessed 2026-09-12.
