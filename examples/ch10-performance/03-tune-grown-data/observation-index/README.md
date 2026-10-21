# Chapter 10 Demo 3 — Evaluate the Chapter 7 `ValueNumeric` index

> **Repository supplement.** The book's Chapter 7 ends its performance
> investigation with a Query Store missing-index recommendation and says
> *"Chapter 10 evaluates possible solutions and their performance, storage,
> and write-cost tradeoffs."* The final Chapter 10 doesn't include that
> evaluation, so this example provides it. It isn't described in the book.

Ask in VS Code Chat (`tune-wardgeneral-data` skill):
**Evaluate the Chapter 7 ValueNumeric index.**

## What it measures

Chapter 7's query aggregates `clinical.Observation` where
`ValueNumeric BETWEEN 90 AND 110`. Without an index on `ValueNumeric` it reads
the whole ~108-million-row table. Query Store recommended:

```sql
CREATE NONCLUSTERED INDEX ... ON clinical.Observation (ValueNumeric) INCLUDE (ObservationType);
```

An index is never free. This example measures both sides on your database:

| Side | How it's measured |
| --- | --- |
| **Read benefit** | The Chapter 7 query, run twice before and twice after the index (the second, warm run is compared): logical reads, CPU ms, elapsed ms, and whether the query actually used the new index. |
| **Write cost** | 500 `clinical.RecordVitals` calls in one transaction, **rolled back**: transaction log bytes per new row and elapsed time, before and after. No rows persist. |
| **Storage cost** | The index's size beside the table's own size, and the build time. |

## Run it

```powershell
./run-demo.ps1             # preview: changes nothing
./run-demo.ps1 -Execute    # run the evaluation, then drop the index
./run-demo.ps1 -Execute -KeepIndex   # keep the index afterwards
```

`-Execute` first drops this example's index if an earlier run left it, so the
"before" numbers are clean. It always drops the index at the end unless you
pass `-KeepIndex`. Evidence goes to `results/runs/<UTC timestamp>/`
(git-ignored): every script's output plus `summary.json`.

Run the scripts yourself in this order: `01-measure-read.sql`,
`02-measure-write.sql`, `03-create-index.sql`, `01-measure-read.sql`,
`02-measure-write.sql`, then `04-cleanup.sql`.

| File | Purpose |
| --- | --- |
| `01-measure-read.sql` | The Chapter 7 query with `STATISTICS IO/TIME`, plus whether the demo index served it. Read-only. |
| `02-measure-write.sql` | 500 `RecordVitals` calls in a rolled-back transaction; reports log bytes and elapsed time. |
| `03-create-index.sql` | Builds `IX_Observation_ValueNumeric_Ch10` **ONLINE**; reports build time and size. |
| `04-cleanup.sql` | Drops only `IX_Observation_ValueNumeric_Ch10`. Safe to repeat. |
| `run-demo.ps1` | Preview-first runner that does all of the above and prints a before/after table. |

## Before you run it

- **Time and cost.** Building an index on ~108 million rows takes minutes and
  adds billed storage while it exists. The build is `ONLINE`, so reads and
  writes continue. Run it at the size Demo 1 leaves (`HS_Gen5_40`) or expect a
  longer build.
- **Storage doesn't shrink by itself.** Dropping the index frees its pages,
  but Hyperscale allocated storage doesn't shrink automatically; see
  [Cost and cleanup](../../README.md#cost-and-cleanup--scale-back-when-you-finish).
- **What the result tells you.** Expect far fewer reads for this query, and
  some extra log per insert because every new observation also writes the
  index. Whether that trade is worth it depends on how often this query runs
  against how many vitals Ward General records; the numbers let you decide
  rather than accepting the recommendation blindly.

The measurement logic was verified on a scaled-down copy of the schema
(LocalDB, 300,000 rows): reads fell about 93%, log bytes per insert roughly
doubled, and cleanup left no index behind. Your numbers on the full database
will differ.
