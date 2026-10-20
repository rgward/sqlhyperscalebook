# Chapter 10 Demo 3 — JSON index

Book prompt (VS Code Copilot Chat, `tune-wardgeneral-data` skill):
**Run the Chapter 10 JSON index demo**

This folder builds a bounded, demo-owned `clinical.LabResultArchive` of about
five million JSON lab documents, runs a `JSON_CONTAINS` query against the
`$.flags` array before and after a JSON index, and captures both actual plans.
It does not touch existing Ward General rows. The full explanation, expected
output, and how to read the plans are in the
[Stage 3 README](../README.md#json-index-sequence).

## Run it

From this folder (the scripts find their files from their own location):

```powershell
./run-demo.ps1            # preview: target database, and that the index build is offline
./run-demo.ps1 -Execute   # approve: run the whole sequence
```

The JSON index build is **offline** for the demo table while it runs, which is
why `-Execute` is an explicit approval. The run always cleans up, and writes its
evidence (actual plans, `plan-summary.csv`, raw output) under
`results/runs/<UTC timestamp>/`. It prints logical reads, CPU, and elapsed time
for the scan, the first indexed run, and the **warm** indexed run — compare the
scan with the warm run, as the book does.

## Run the scripts yourself

Run them in order, in the MSSQL extension, SSMS, or `sqlcmd`:

1. `01-setup.sql` — create five critical lab-result documents and five million
   routine documents in 50,000-row batches.
2. `02-before.sql` — capture the baseline plan, reads, and duration.
3. `03-create-index.sql` — perform the offline JSON index build with
   array-search optimization.
4. `04-after.sql` — repeat the identical predicate twice (first run, then warm)
   and compare the evidence.
5. `05-cleanup.sql` — drop only the JSON index and archive table this example
   created.

## Prerequisites and cost

See the [Chapter 10 prerequisites](../../README.md#prerequisites). The demo runs
against `wardgeneral` at whatever size Demo 1 left it; when you finish Chapter
10, see [Cost and cleanup](../../README.md#cost-and-cleanup--scale-back-when-you-finish).
