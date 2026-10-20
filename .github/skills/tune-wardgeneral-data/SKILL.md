---
name: tune-wardgeneral-data
description: 'Run the implemented parts of Chapter 10 Demo 3: JSON indexing and memory grant feedback on Ward General. USE WHEN the reader says "Run the Chapter 10 JSON index demo", "Run the Chapter 10 memory grant feedback demo" (the book''s prompts; run only the named sequence), "run Chapter 10 Demo 3", "demo JSON indexing", "run the JSON index demo", "show memory grant feedback", or "run the MGF demo". Owns the self-contained LabResultArchive JSON-index sequence and the self-contained row-mode memory grant feedback scenario; Observation tuning is deferred. The JSON index build is offline and requires explicit acknowledgment. Do not scale compute, grow the database, or add named replicas.'
---

# Tune Ward General

Follow `examples/ch10-performance/03-tune-grown-data/README.md`.

## Boundaries

- Use Query Store and actual plans from Chapter 7; do not re-teach the toolkit.
- The JSON-index and memory grant feedback sequences are independent of Demo 2
  growth and modify no existing Ward General rows.
- The JSON-index sequence owns only `clinical.LabResultArchive` and its JSON
  index.
- `CREATE JSON INDEX` is an offline operation. Explain the blocking boundary
  and obtain explicit acknowledgment before running the build script.
- Recheck current Azure SQL Database documentation before manuscript freeze;
  the reference status is still moving.
- The memory grant feedback sequence is independent of Demo 2 growth. It owns
  only `clinical.ShiftReportArchive` and
  `clinical.DemonstrateMemoryGrantFeedback`.

## JSON-index workflow

1. Run `json-index/run-demo.ps1` to preview the target and offline-build
  boundary.
2. Run `json-index/run-demo.ps1 -Execute` only after the reader accepts that
  boundary. It performs setup, captures `before-index.sqlplan`, builds the
  offline index, runs the indexed query twice and captures
  `after-index-first-run.sqlplan` and `after-index.sqlplan` (warm), summarizes
  all three, and always cleans up.
3. Use `plan-summary.csv` to confirm the transition from a Clustered Index Scan
  over 5,000,005 rows to an Index Seek with `IndexKind="Json"` returning five
  rows. Report logical reads, CPU ms, and elapsed ms for **Before index** and
  **After index (warm)** — the book's comparison — and note the first indexed
  run separately as including compilation. Say timings vary by environment.
4. If the reader wants graphical proof, have them open each `.sqlplan` through
  SSMS **File > Open > File**. Compare the baseline scan on
  `PK_LabResultArchive` with the indexed seek on
  `json_index_search_optimization_nci` and verify `IndexKind="Json"`.
5. On the manual SQL path, run `json-index/01-setup.sql`,
  `json-index/02-before.sql`, accept the offline boundary, run
  `json-index/03-create-index.sql`, then `json-index/04-after.sql`.
6. On the manual path, run `json-index/05-cleanup.sql` when finished. The
  PowerShell runner already invokes cleanup in `finally`.

## Memory grant feedback workflow

1. Run `memory-grant-feedback/run-demo.ps1` to preview the target.
2. Run `memory-grant-feedback/run-demo.ps1 -Execute`. It performs setup,
  captures actual plans for executions 1 and 2, executes all eight calls,
  summarizes plan and Query Store feedback evidence, and always cleans up.
3. Use the generated `plan-summary.csv`, `execution-1.sqlplan`, and
  `execution-2.sqlplan` under `memory-grant-feedback/results/runs/`. Confirm
  execution 1 has `SpillToTempDb` and execution 2 has no Sort warning.
4. If the reader wants graphical proof, have them open each `.sqlplan` through
  SSMS **File > Open > File**. On execution 1, inspect the Sort warning and
  spill level 1; on execution 2, confirm the warning is absent. On each root
  SELECT, compare `IsMemoryGrantFeedbackAdjusted`, requested grant, and actual
  rows. Both plans must retain the same covering Index Seek.
5. If running the SQL manually, start with `memory-grant-feedback/01-setup.sql`.
  It makes no database-scoped
  configuration changes, leaves automatic statistics enabled, creates current
  `FULLSCAN` statistics, and stops if the required settings are unavailable.
6. Run `memory-grant-feedback/02-run.sql` once. Compare the first execution with
  the later executions using grant, used-grant, spill-page, plan-generation,
  actual-plan, and Query Store feedback evidence.
7. Attribute intervention from `sys.query_store_plan_feedback`. The validated
  result is MGF `FEEDBACK_VALID`; CE feedback did not intervene in the clean
  eight-execution run.
8. Report the grant, spill, CPU, and elapsed-time change from the reader's
  actual run. Compare it with the canonical validation, where the grant changed
  from 9.09 MB to 599.13 MB, a 390.50 MB spill disappeared, and execution 2 was
  52% faster. Do not substitute those reference values for the reader's
  measurements. Confirm plan generation remained 1 and the covering index seek
  did not change.
9. On the manual SQL path, run `memory-grant-feedback/03-cleanup.sql` when the
  reader is finished or before repeating setup. The PowerShell runner already
  invokes this cleanup in `finally`.

Observation tuning remains supporting work until its scripts are implemented.
Do not fabricate those results or treat a missing-index recommendation as an
instruction to create an index.
