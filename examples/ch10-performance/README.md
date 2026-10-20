# Chapter 10 — Scale and Tune Ward General

Chapter 10 continues the same Ward General system built in Chapters 2 through
9. It does not deploy a replacement database or introduce a disconnected
benchmark. The reader increases load on the existing application, scales its
compute, grows its existing clinical data, tunes the structures that became
large, and reviews how the existing vector-search path uses a named replica.

## The progression

| Stage | Reader action | What carries forward |
| --- | --- | --- |
| [1. Scale compute](01-scale-compute/) | Run the same Chapter 2 procedure workload at `HS_Gen5_8`, `HS_Gen5_16`, and `HS_Gen5_40` through one approval-gated orchestration. | Chapter 3 explains why no data moves. Chapter 7 supplies the measurements. Chapter 9 already established the separate cutover/retry behavior. |
| [2. Grow data and find the constraint](02-grow-data/) | Drive 64 concurrent writers for five minutes, show automatic 10 GB storage allocation, and measure the write path. Repeat the interval when more data is useful. | The database, schema, security posture, application, and Standard-series hardware remain unchanged. Only data volume changes. |
| [3. Tune Ward General](03-tune-grown-data/) | Run independent JSON-index and memory grant feedback demonstrations with bounded, demo-owned clinical data. | Chapter 7's plan and runtime evidence remain the measurement model; these examples do not depend on stage 2 growth. |

Each stage has its own repository skill. Use `scale-and-tune-wardgeneral` only
for the complete three-stage progression; use the owning skill named in the
stage README for an individual demo.

The sequence changes one governing constraint at a time:

1. Scale **up** when active work needs more CPU, memory, or workers.
2. Grow **data** and use the evidence to identify the governing constraint.
3. **Tune** access paths after the data has grown.

The book separately revisits the Chapter 5 Research page to explain how
`wardgeneral-research` isolates vector-search compute and how additional named
replicas can provide more aggregate read capacity. That review is conceptual,
not a fourth runnable example.

## What the reader already has

- The `wardgeneral` Hyperscale database, schema, seed data, procedures, and HA
  configuration from Chapter 2 — plus the `wardgeneral-research` named replica
  if you ran the optional `add-replicas.ps1` step (no Chapter 10 demo needs it).
- The page-server, log-service, RBPEX, and replica model from Chapter 3.
- The Ward General application, passwordless connection factory, connection
  pooling, and retry policy from Chapter 4.
- Native JSON, embeddings, DiskANN, and `clinical.SearchSimilarNotes` from
  Chapter 5.
- The agentic workflow and its connection-density motivation from Chapter 6.
- Query Store, waits, DMVs, Azure Monitor, and Extended Events from Chapter 7.
- The Chapter 8 security posture, including row-level security when enabled.
- The Chapter 9 evidence that a compute cutover can reset a connection and that
  the application must tolerate it.

## Reader-run exercises

All three stages are reader-run exercises. Each Stage 2 execution runs one
five-minute write interval and reports the growth that actually occurred.
Readers can repeat it when they want more data.

Every Azure compute change is preview-first. A script must print the current
and requested configuration and require explicit approval before changing a
billable resource.

## Cost and cleanup — scale back when you finish

Demo 1 ends with `wardgeneral` at **`HS_Gen5_40`**, and the book leaves it there
for Demo 2. That is five times the Chapter 2 compute, and the HA replica is
billed at the same size as the primary, so the higher rate runs **every hour
until you scale back** — whether or not anything is using the database. No
script in this chapter scales down automatically.

When you finish Chapter 10 — or stop partway and won't continue soon — preview
the return to the Chapter 2 size, then approve it:

```powershell
cd examples/ch10-performance/01-scale-compute
./scale-compute.ps1 -TargetServiceObjective HS_Gen5_8            # preview, changes nothing
./scale-compute.ps1 -TargetServiceObjective HS_Gen5_8 -Approve   # scale back
```

It reads the server and database from `examples/ch04-first-app/ch04.env`, the
same as the demos. Scaling is online; expect a brief connection reset at the
cutover (Chapter 9).

Other things that keep billing after this chapter:

- **Storage from Demo 2.** Each five-minute interval adds roughly 12 GB of
  clinical history, and allocated storage grows in 10 GB steps. Hyperscale bills
  allocated storage; the runner never deletes generated data or shrinks files.
  Only repeat the interval when you want more data.
- **A Chapter 9 geo-secondary, if you kept it.** It bills separately and is not
  scaled with the primary. Remove it with Chapter 9's `cleanup-geo-replica.ps1`
  if you no longer need it.
- **The optional `wardgeneral-research` named replica** bills at its serverless
  minimum while idle.

To stop all charges, delete the resources as described in the Chapter 2 README.

## Author validation results

| Stage | Status |
| --- | --- |
| 1 | Orchestrated `HS_Gen5_8 → HS_Gen5_16 → HS_Gen5_40` progression, with one explicit approval covering both displayed scale changes, passwordless `sqlsim` load at each size, and focused measurements. |
| 2 | **Complete.** Live-validated on `wardgeneral` at `HS_Gen5_40`: one five-minute interval added 12.065 GB, grew allocated data files automatically from 20 GB to 40 GB, reached 70.35 MiB/s peak actual log throughput, and completed 687 transactions without failure. |
| 3 | JSON-index path complete: 5,000,005-row live validation reduced logical reads from 162,050 to 24. Query-feedback path complete: in the canonical run, MGF eliminated a 390.50 MB spill and cut elapsed time by 52% on execution 2; CE feedback did not intervene. Both paths have verified cleanup; Observation tuning remains deferred. |

## Sources

- [Microsoft Learn — Hyperscale secondary replicas](https://learn.microsoft.com/azure/azure-sql/database/service-tier-hyperscale-replicas), accessed 2026-09-11.
- [Microsoft Learn — Intelligent Query Processing](https://learn.microsoft.com/sql/relational-databases/performance/intelligent-query-processing), accessed 2026-09-11.
- [Microsoft Learn — `CREATE JSON INDEX`](https://learn.microsoft.com/sql/t-sql/statements/create-json-index-transact-sql), accessed 2026-09-11. At that time, the reference labeled this feature preview and listed SQL Server 2025. Check the current Azure SQL Database documentation and feature availability before running the JSON-index example.
