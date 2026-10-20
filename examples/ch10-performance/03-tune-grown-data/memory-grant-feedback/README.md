# Chapter 10 Demo 3 — Memory grant feedback

Book prompt (VS Code Copilot Chat, `tune-wardgeneral-data` skill):
**Run the Chapter 10 memory grant feedback demo.**

This folder builds a bounded, demo-owned `clinical.ShiftReportArchive` of five
million nursing shift reports with correlated predicates, so the first execution
underestimates its memory grant and spills its sort to `tempdb`. Memory grant
feedback corrects the grant on the next execution. It does not touch existing
Ward General rows or change database-scoped configuration. The full
explanation, expected output, and how to read the plans are in the
[Stage 3 README](../README.md#memory-grant-feedback-sequence).

## Run it

From this folder (the scripts find their files from their own location):

```powershell
./run-demo.ps1            # preview: the target database
./run-demo.ps1 -Execute   # approve: run the whole sequence
```

`-Execute` runs setup, executes the query eight times, saves actual plans for
executions 1 and 2, writes `plan-summary.csv`, reports Query Store feedback, and
always runs cleanup. Evidence goes under `results/runs/<UTC timestamp>/`.

The console summary shows, for executions 1 and 2, the elapsed and CPU time
from each actual plan's `QueryTimeStats`, the sort spill, and the granted and
used memory. It then prints how much faster (or slower) execution 2 was than
execution 1. The book reports about 40% faster; your numbers will vary. Finally
it prints each `sys.query_store_plan_feedback` row's feature and state, which
should show memory grant feedback as `FEEDBACK_VALID`. The same rows are saved
to `query-store-feedback.csv`. Grant, spill, and elapsed time for all eight
executions are in `run-output.txt`.

## Run the scripts yourself

Run them in order, in the MSSQL extension, SSMS, or `sqlcmd`:

1. `01-setup.sql` — verify compatibility level, Query Store, and memory grant
   feedback settings; create and populate `clinical.ShiftReportArchive`; build
   `FULLSCAN` statistics; and create `clinical.DemonstrateMemoryGrantFeedback`.
2. `02-run.sql` — execute the same cached statement eight times, returning
   actual plans for executions 1 and 2 and reporting grant, spill, elapsed
   time, and Query Store feedback.
3. `03-cleanup.sql` — drop only the procedure and table this example created.
   Run it before repeating setup.

## Prerequisites and cost

Needs database compatibility level 160 or higher (Chapter 2 deploys 170) and
Query Store in `READ_WRITE`. See the
[Chapter 10 prerequisites](../../README.md#prerequisites). When you finish
Chapter 10, see [Cost and cleanup](../../README.md#cost-and-cleanup--scale-back-when-you-finish).
