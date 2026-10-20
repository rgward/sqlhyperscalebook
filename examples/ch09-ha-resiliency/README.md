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

## Prerequisites

Every example in this chapter needs:

- **Chapter 2 complete** — `wardgeneral` deployed with its HA replica, schema
  and seed loaded.
- **PowerShell 7+** (`pwsh`).
- **Azure CLI** signed in with `az login`, with the subscription that holds the
  database selected (`az account show`).
- **The new Go-based `sqlcmd`** (not the legacy ODBC one). Check with
  `sqlcmd --version`; install with `winget install --id Microsoft.Sqlcmd`.
  Install it **before** the failover demo: its evidence step runs after the
  failover, and a database can be failed over only once every 15 minutes.
- **`examples/ch04-first-app/ch04.env`** filled in with `WardGeneral__Server`
  (full `.database.windows.net` name) and `WardGeneral__Database`. Add `RG=`
  only if your resource group isn't `rg-collierhealth`.
- **A Microsoft Entra identity that is the server's Entra admin** (the Chapter
  2 deployer). The PITR status check reads `sys.dm_operation_status` in `master`.
- **Rights to change the database and create resources** in the resource group
  (Contributor or SQL Server Contributor): failover, restore, and geo-replica
  creation are control-plane operations.

Per example:

| Example | Also needs |
| --- | --- |
| `failover/` | **.NET 10 SDK** — the retry probe builds against Chapter 4's `WardGeneral.Data`. Reuses Chapter 7's `availability/availability.sql`. |
| `pitr/` | Nothing more. The restored copy is **billable** until cleanup. |
| `geo/` | Permission to create a logical server and set its Entra admin. If Chapter 8 switched the source to a customer-managed key, rights to grant the new server access to that Key Vault key. The target server and secondary are **billable** until cleanup. |

**All data is synthetic. There is no real patient data (PHI) here.**
