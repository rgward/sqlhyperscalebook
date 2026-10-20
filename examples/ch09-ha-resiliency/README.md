# Chapter 9 — High Availability and Resiliency in Hyperscale

Chapter 9 has three guided examples. The first shows what the Ward General
application's existing retry policy does while Azure SQL fails the database
over. The second uses point-in-time restore to create a current, lower-compute
copy of Ward General for isolated testing. The third creates and verifies a
cross-region Hyperscale geo-secondary in the source region's Azure pair.
Together they cover application availability, data recovery, and regional
resiliency.

| Folder | Question | Status |
| --- | --- | --- |
| [`failover/`](failover/) | How does the same retry provider used by Ward General carry an application request through a manual failover? | Live validated on 2026-09-07 |
| [`pitr/`](pitr/) | How can Ward General create a current-as-of-start, lower-compute Hyperscale serverless copy for isolated testing by using PITR? | Live validated on 2026-09-07 |
| [`geo/`](geo/) | How can Ward General create an Entra-only logical server in another region and add a Hyperscale geo-secondary? | Live validated (Central US → East US 2) with CMK on 2026-09-08; paired-region default added 2026-10 |

Start with the README inside the folder for the demonstration being performed.
All three examples use the existing Chapter 2 `wardgeneral` deployment. The
failover example also references the Chapter 4 `WardGeneral.Data` project so
the retry settings have one source of truth.

The matching skills are `test-hyperscale-failover`,
`recover-wardgeneral-pitr`, and `deploy-wardgeneral-geo-replica`. They drive the
same commands and approval gates as the READMEs.

The chapter explains HA replica count, continuous priming, failover groups,
zone redundancy, backup policy, replica lag, maintenance windows, and RPO/RTO
commitments without packaging each topic as another guided example. Chapter 7
remains the source for availability evidence and replica-state diagnostics.

> **New here?** Read the [repository README](../../README.md) first. The examples
> assume the Chapter 2 `wardgeneral` deployment and synthetic dataset already
> exist.

**All data is synthetic. There is no real patient data (PHI) here.**
