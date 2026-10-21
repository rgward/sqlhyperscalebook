# Chapter 9 — High Availability and Resiliency in Hyperscale

> **Figures:** this chapter's book figures are in [`figures/ch09-ha-resiliency/`](../../figures/ch09-ha-resiliency/),
> listed with their captions in the [figures index](../../figures/README.md#chapter-9).

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

## Supplement: backups at a glance

This section is a repository supplement, not text from the book. It summarizes
the backup and restore options Chapter 9 walks through, using Microsoft Learn
(accessed 2026-10-20). Limits and preview status change, so check the linked
pages before you rely on a value.

| Option | What it is | How often | Kept for | Restores to | Size of operation |
| --- | --- | --- | --- | --- | --- |
| [Automated backups and PITR](https://learn.microsoft.com/azure/azure-sql/database/hyperscale-automated-backups-overview) | Storage snapshots of the data files plus the retained transaction log. No full, differential, or log backups. | Continuous: each file is snapshotted on its own cadence and the log is kept as is. | 1–35 days (default 7). | A new database on the same logical server. | Not size-of-data in the same region; it becomes size-of-data if you change storage or zone redundancy during the restore. |
| [Long-term retention (LTR)](https://learn.microsoft.com/azure/azure-sql/database/long-term-retention-overview) | Backups copied to separate long-term storage by a policy. | Weekly, monthly, and/or yearly, per the policy. | Up to 10 years. | Any server in the same subscription. | Size-of-data (the book: LTR restores can't use snapshots). |
| [Immutable LTR backups](https://learn.microsoft.com/azure/azure-sql/database/backup-immutability) | LTR backups stored write-once, read-many so no one can modify or delete them. | Applies to LTR backups. | Time-based: until the backup's retention ends. Legal hold (preview): until you remove it. | Same as LTR. | Same as LTR. |
| [Geo-restore](https://learn.microsoft.com/azure/azure-sql/database/recovery-using-backups#geo-restore) | A restore from geo-replicated backups. Needs geo-redundant or geo-zone-redundant backup storage. | Uses the most recent geo-replicated backups. | — | Any logical server in any Azure region. | Size-of-data; faster to the paired region. |
| [Database copy](https://learn.microsoft.com/azure/azure-sql/database/database-copy#database-copy-for-hyperscale-databases) | A transactionally consistent copy as of when the copy started. | On demand. | Until you delete it. | The same or a different logical server. | Fast from snapshots in the same region with the same storage redundancy; size-of-data otherwise. |

Two settings that affect every row:

- **Backup storage redundancy** (LRS, ZRS, RA-GRS, RA-GZRS) is chosen when the
  database is created and can't be changed later. Data and backups share the
  same storage, so the choice applies to both. LRS or ZRS turns off geo-restore.
- **Cost:** backup storage is billed per GB per month, and an amount equal to
  the database size is free. Write-heavy workloads change more pages, which
  produces larger snapshots and more log.

### Questions from readers

**Do I still need to run `DBCC CHECKDB`?** It isn't available in Hyperscale.
The book's *Data Integrity* section covers this: run
`DBCC CHECKTABLE ('schema.table') WITH TABLOCK` on individual tables at a time
you choose, because it uses significant resources. Microsoft also verifies page
checksums, detects lost writes, verifies pages during backups and during every
restore, and can repair some pages automatically from another replica. See
[Data integrity in Azure SQL Database](https://learn.microsoft.com/azure/azure-sql/database/data-integrity).

**Can a snapshot backup become corrupt, and should I still test restores?**
Learn documents page verification during service-managed backups and during
each restore, with any problem alerting the engineering team. Testing restores
is still how you learn your own restore time. The [pitr/](pitr/) example in this
chapter is a ready-made restore test.

**Are named replicas backed up?** A named replica uses the same page servers as
the primary and holds no copy of the data. Hyperscale backups are snapshots of
those page-server data files plus the log, which belong to the primary
database. Learn doesn't document a separate backup or retention setting for
named replicas. See
[Hyperscale secondary replicas](https://learn.microsoft.com/azure/azure-sql/database/service-tier-hyperscale-replicas#named-replica).

**Do snapshot backups grow when I add data?** Yes. Learn says backup costs are
higher for workloads that add, modify, or delete large volumes of data, because
those workloads change data pages more often and generate more log. Mostly
read-only workloads have smaller backup costs. See
[Backup storage costs](https://learn.microsoft.com/azure/azure-sql/database/hyperscale-automated-backups-overview#backup-storage-costs).

## Links from the book

Every web link printed in Chapter 9, in the order it appears, so you can click
instead of typing it. Cross-references to other chapters and links to this
repository are left out.

- Azure SQL service level agreement (SLA) — <https://aka.ms/azuresqlsla>
- Configurable retry logic in Microsoft.Data.SqlClient — <https://learn.microsoft.com/sql/connect/ado-net/configurable-retry-logic>
- Databases - Failover REST API — <https://learn.microsoft.com/rest/api/sql/databases/failover>
- Ways to trigger a manual failover — <https://aka.ms/testazuresqlfailover>
- Azure availability zones — <https://azure.microsoft.com/explore/global-infrastructure/availability-zones>
- Azure regions and zone support — <https://learn.microsoft.com/azure/reliability/regions-list>
- Azure paired regions — <https://aka.ms/azurepairedregions>
- Immutable backups — <https://learn.microsoft.com/azure/azure-sql/database/backup-immutability>
- Point-in-time restore (PITR) — <https://aka.ms/sqlpitr>
- Database copy — <https://aka.ms/azuresqldbcopy>
- Planned maintenance events — <https://learn.microsoft.com/azure/azure-sql/database/planned-maintenance>
