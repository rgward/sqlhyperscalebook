# Chapter 2 — Getting Started

> **Figures:** this chapter's book figures are in [`figures/ch02-getting-started/`](../../figures/ch02-getting-started/),
> listed with their captions in the [root README](../../README.md#chapter-2).

Provision an Azure SQL **Hyperscale** database, connect to it, build the
through-line schema, and seed it with fully synthetic data. This is the database
every later chapter builds on: the **Ward General Hospital** database
(`wardgeneral`) on the **Collier Health** logical server (`collierhealth`).

> **New here?** Read the [repository README](../../README.md) first — it covers the
> scenario, prerequisites (VS Code, GitHub Copilot, PowerShell 7, Azure CLI, the
> MSSQL extension, an Azure subscription), and how to run the guided deploy with
> the `deploy-hyperscale` Copilot skill.

## The flow

Five moves, in order:

1. **Deploy** — create the logical server + Hyperscale database with one HA
   replica (`provision-hyperscale.ps1`).
2. **Optional: add the named replica** — run `add-replicas.ps1` to create the
   `wardgeneral-research` named replica. It leaves the HA replica count at one.
   Chapter 3 examines it as an architectural object, and Chapter 5's Research
   page is the first thing to actually use it; skip it now and run it when you
   get there.
3. **Connect & prove it's SQL Server** — run `connect-and-verify.sql`.
4. **Build the schema** — run `01`→`04` in order.
5. **Seed & verify** — run `05-seed.sql`, then `verify-data.sql`.

You can drive all of this through Copilot — the book's prompt is *"I'd like to
deploy an Azure SQL Hyperscale database"*, and *"deploy my Hyperscale database"*
works too; either runs the `deploy-hyperscale` skill — or run the scripts by hand
as described below. After the primary deploy succeeds, the guided path explains
the named replica's cost and asks for separate approval before it runs
`add-replicas.ps1`; it never creates that billable replica silently.

> **Tip — a third way to verify.** After the deploy, run
> `verify-activity-log.ps1` for a control-plane check: it summarizes the Azure
> Activity Log (every operation that built the database) and flags any failures.
> Or ask Copilot, as the book does: *"Verify my deployment by summarizing the
> Azure Activity Log."*
> That's the deploy proof; `connect-and-verify.sql` is the tier proof and
> `verify-data.sql` is the data proof — same database, three angles.

## Files in this folder

| File | Type | What it does |
|---|---|---|
| `provision-hyperscale.ps1` | PowerShell | Reuses the resource group if it already exists (so SQL Server Contributor on an administrator-created group is enough) or creates `rg-collierhealth`, then creates the `collierhealth` logical server and the `wardgeneral` Hyperscale database in one `az sql db create` — provisioned, single, **1 HA replica, zone-redundant, GeoZone backup**. Mixed SQL + Entra auth. Calls `estimate-cost.ps1` at the end. |
| `estimate-cost.ps1` | PowerShell | Prints a live, itemized monthly cost estimate for the deployed Hyperscale shape from the public Azure Retail Prices API, plus the deploy-time cost-vs-resilience levers (inside Hyperscale, drop the HA replica / zone redundancy ≈ −50% compute; Zone vs GeoZone backup). For GP ZR comparisons, use the Azure portal cost summary or Pricing Calculator because GP ZR uses a different meter shape. No dollar figures are hard-coded. |
| `verify-activity-log.ps1` | PowerShell | Read-only control-plane check: summarizes the Azure **Activity Log** for `rg-collierhealth` (every operation ARM ran to build the database) — events by status, by operation, most-recent table, and a **failure flag**. A clean deploy shows all `Succeeded`. Widen the window with `$env:OFFSET='1d'` (default 6h). |
| `connect-and-verify.sql` | SQL | Proves it's SQL Server: `@@VERSION`, `DATABASEPROPERTYEX`, service objective, and the governing limits (workers, sessions, log rate, IOPS, memory, 128 TB ceiling, collation, compatibility level) in human units. |
| `01-schemas.sql` | SQL | Creates the `clinical` and `ops` schemas. |
| `02-tables.sql` | SQL | Creates all 16 tables — clustered keys, FKs, constraints, and the four native `json` columns. |
| `03-views.sql` | SQL | Creates `clinical.vPatientChart` and its supporting chart views. |
| `04-procedures.sql` | SQL | Creates the eleven read/write procedures (admit, discharge, record vitals, place order, file lab, add note/diagnosis/allergy, `SearchEncounters`, chart reads). `SearchEncounters` supports optional ID, date, status, unit, department, and provider-name filters and returns readable encounter summaries. They are the hospital's contract, not this book's app's: the same procedures are what Data API Builder and the agent expose in Chapter 6. |
| `05-seed.sql` | SQL | Seeds the database to roughly **12 GB** of fully synthetic data (Observation is the ~108M-row anchor). Runs ~5–15 min — log-rate gated. |
| `verify-data.sql` | SQL | Read-only PASS/FAIL check with per-table volume checks. You want it to end with **`ALL CHECKS PASSED`**. |
| `add-replicas.ps1` | PowerShell | **Optional.** Creates the **`wardgeneral-research`** named replica (serverless `HS_S_Gen5_8`) and prints the resulting topology; the HA replica count stays at one. A named replica is read-only, looks like a separate database, and is **not** a failover target. Chapter 3 dissects it; Chapter 5 uses it. |

## Deploy inputs (environment variables)

`provision-hyperscale.ps1` reads its inputs from environment variables, each with
a sensible default. Set any overrides **before** running it (the
`deploy-hyperscale` skill sets these for you during the guided deploy):

| Variable | Default | Notes |
|---|---|---|
| `LOC` | `eastus2` | Region — pick one with availability-zone support and `HS_Gen5` quota. |
| `RG` | `rg-collierhealth` | Resource group. An existing group is reused unchanged; a missing one is created (needs subscription Contributor). If you use a non-default name, also set `RG=` in `ch04-first-app/ch04.env` so later chapters find it. |
| `SRV` | `collierhealth-<random>` | Logical server — must be globally unique. |
| `DB` | `wardgeneral` | The Hyperscale database. |
| `SLO` | `HS_Gen5_8` | Compute shape — changeable later. |
| `HA_REPLICAS` | `1` | Required for zone redundancy. |
| `ADMIN_OBJECT_ID` | *(required)* | Entra object ID for the server's Entra admin. The guided deploy fills the three `ADMIN_*` values from your signed-in account by default (as the book does); by hand, `az ad signed-in-user show --query "{id:id, upn:userPrincipalName}"`. |
| `ADMIN_DISPLAY_NAME` | `Collier Health DBAs` | Entra admin display name (your UPN when you use your own account). |
| `ADMIN_TYPE` | `Group` | `User` \| `Group` \| `ServicePrincipal` — `User` for your own account. |
| `SQL_ADMIN_USER` | `wardadmin` | Mixed-auth SQL admin login (Ch 8 moves to Entra-only). |
| `SQL_ADMIN_PASSWORD` | *(required)* | Set in the environment — never hard-coded. |

## Running the SQL scripts (and re-running them)

Run `01`→`05` **in order once**, then `verify-data.sql`. **You never drop the
database to start over:**

- **Reload just the data** → re-run `05-seed.sql` alone (truncate + reseed).
- **Rebuild after a schema change** → re-run `02`→`05` (`02` drops and recreates
  the tables, discarding data).
- `01` is a guarded no-op; `03`/`04` are `CREATE OR ALTER` (safe anytime).

### If you have already deployed the Chapter 5 scripts

Only relevant on a **second** run of `05-seed.sql`, and only if you have been
through Chapter 5. Two Chapter 5 tables take a foreign key into data this seed
owns — `clinical.ClinicalNoteEmbeddings` on `ClinicalNote`, and
`clinical.AIAssistanceLog` on `Encounter` — and a foreign key blocks `TRUNCATE`
outright, whether or not the child holds a single row. So the seed **drops both**
before it reloads. On a first run neither exists and both drops are no-ops.

`clinical.AIAssistanceLog` has to be dropped rather than emptied. Chapter 5
creates it as an **append-only ledger table** for the tamper-evident audit trail,
and an append-only ledger table supports neither `DELETE` nor `TRUNCATE` — see
[Ledger considerations and limitations](https://learn.microsoft.com/sql/relational-databases/security/ledger/ledger-limits),
items 3 and 4. `DROP` is the only route that works.

Dropping a ledger table is a **soft delete by design**. The object is renamed to
`MSSQL_DroppedLedgerTable_*` and physically retained so the ledger digest stays
verifiable ([DROP TABLE, Remarks](https://learn.microsoft.com/sql/t-sql/statements/drop-table-transact-sql#remarks)).
Every reseed leaves one more of these behind, and **they are supposed to stay** —
that is the cost of a tamper-evident trail, not a leak. Leave them alone.

So after re-running `05-seed.sql`, redeploy Chapter 5: `06-ai-embeddings.sql`,
`07-vector-index.sql`, `08-ai-assistance.sql`. The Chapter 4 app runs fine
without them so long as the `AiAssistance` feature flag is off.

Every `.sql` file opens with the seven-line `SET`-options preamble so the scripts
behave identically in the MSSQL extension, SSMS, or `sqlcmd`. See the
[repository README](../../README.md) for the full re-run and `SET`-options
explanation.

## Using the free Azure SQL Database offer instead

The book (Chapter 2, "Azure Subscription") notes that you can follow the SQL and
application work on the [Azure SQL Database free offer](https://aka.ms/freedboffer)
instead of Hyperscale. Know what that changes before you start:

- **The guided deploy always creates billable Hyperscale.** The
  `deploy-hyperscale` skill, `provision-hyperscale.ps1`, and `add-replicas.ps1`
  don't create a free-offer database. Create it yourself in the portal (Azure SQL
  hub → **Create a database** → **Start free**) and skip those three.
- **Name it `wardgeneral`**, or set `WardGeneral__Database` in
  `examples/ch04-first-app/ch04.env` to the name you used. Add your Microsoft
  Entra account as the server's Entra admin so the passwordless scripts and app
  can connect.
- **What still works:** `connect-and-verify.sql` (it will report General
  Purpose, not Hyperscale), `01`→`05`, `verify-data.sql`, and the SQL and
  application work that builds on them.
- **What needs a real Hyperscale database**, per the book: the Chapter 3
  architecture deep-dive, named replicas (Chapter 2's optional step and Chapter
  5's Research page), Chapter 6's agents, the Hyperscale observability signals in
  Chapter 7, and Chapters 9 and 10. Several of those scripts check for Hyperscale
  and stop. There's also no HA replica or zone redundancy to choose.
- **Mind the monthly allowance.** Each free database gets 100,000 vCore seconds
  of serverless compute, 32 GB of data, and 32 GB of backup storage per month.
  The ~12 GB seed fits, but General Purpose has a lower log rate than Hyperscale,
  so `05-seed.sql` takes longer and uses a noticeable share of the month's vCore
  seconds. Watch **Free amount remaining** on the database's Overview page, and
  disconnect tools when you're done — an open connection keeps the database from
  auto-pausing.
- **Choose what happens at the limit.** *Auto-pause the database until next
  month* keeps it free; *Continue using database for additional charges* bills
  you at General Purpose serverless rates and can't be switched back.

Check the [free offer documentation](https://learn.microsoft.com/azure/azure-sql/database/free-offer)
for current limits — they can change after the book.

## Cost and cleanup

A Hyperscale database **bills from the moment it's created**, for compute (the
primary and its HA replica) and storage, whether or not anything is connected.
Stopping the app or closing VS Code does not stop the charges.

To delete what you deployed and come back to it later, use the Azure portal
(or `az`):

- **Delete the resource group** (`rg-collierhealth` by default) — if it holds
  only this book's resources. Open it first and check what's in it: if you've
  gone on to later chapters it may also hold the Chapter 5 AI resources, a
  Chapter 7 or 8 Log Analytics workspace, or a Chapter 8 Key Vault.
- **Or delete the logical server** if you can't delete the group (for example,
  on the least-privilege path where an administrator owns it). Deleting the
  server deletes every database on it, including the `wardgeneral-research`
  named replica — but not the separate Chapter 9 geo-secondary server, which
  you delete on its own (or with that chapter's `cleanup-geo-replica.ps1`).

Deleting the group removes everything in it, including that geo-secondary
server. The Chapter 5 AI resources are soft-deleted when removed, so use that
chapter's `reset-ai-azure.ps1` if you plan to recreate them with the same names.
Each chapter's README describes its own cleanup.

To redeploy afterwards, run this chapter again from the top.

## A note on the data

**All data is synthetic. There is no real patient data (PHI) here — ever.** The
dataset was generated with AI assistance and, while plausible, may not accurately
represent real medical, clinical, laboratory, or billing data. It is for
educational and illustrative purposes only and must not be used for clinical,
diagnostic, or any real-world healthcare decision-making.

## Links from the book

Every web link printed in Chapter 2, in the order it appears, so you can click
instead of typing it. Cross-references to other chapters and links to this
repository are left out.

- Visual Studio subscriptions (monthly Azure credits) — <https://visualstudio.microsoft.com/subscriptions>
- Azure free trial — <https://aka.ms/azurefree>
- Azure for Students — <https://aka.ms/azurestudent>
- Azure SQL Database free offer — <https://aka.ms/freedboffer>
- Azure role-based access control (RBAC) — <https://aka.ms/azurerolebasedaccesscontrol>
- Azure portal — <https://portal.azure.com>
- Azure CLI (az) — <https://aka.ms/azcli>
- Azure PowerShell — <https://learn.microsoft.com/powershell/azure>
- Bicep — <https://aka.ms/bicep>
- Terraform — <https://developer.hashicorp.com/terraform>
- Azure REST API reference — <https://learn.microsoft.com/rest/api/azure>
- Azure SQL REST API reference — <https://learn.microsoft.com/rest/api/sql>
- Visual Studio Code — <https://aka.ms/vscode>
- MSSQL extension for VS Code — <https://aka.ms/vscodemssql>
- SQL Server Management Studio (SSMS) — <https://aka.ms/ssms>
- sqlcmd (go-sqlcmd) — <https://aka.ms/sqlcmd>
- SQL Server PowerShell modules — <https://aka.ms/sqlpowershell>
- SQL Database Projects — <https://aka.ms/sqlprojects>
- GitHub Copilot CLI — <https://github.com/features/copilot/cli/>
- GitHub Copilot desktop app — <https://github.com/github/app>
- AI model choices for GitHub Copilot — <https://docs.github.com/copilot/how-tos/use-ai-models>
- Microsoft Foundry models — <https://learn.microsoft.com/azure/foundry/concepts/foundry-models-overview>
- HammerDB — <https://www.hammerdb.com>
- sqlsimtools (workload simulation) — <https://aka.ms/sqlsimtools>
- FabCon and SQLCon 2026 announcements (Fabric Database Hub) — <https://aka.ms/FabCon-SQLCon-2026-news>
- VS Code download — <https://code.visualstudio.com>
- GitHub Copilot — <https://github.com/features/copilot>
- PowerShell 7 — <https://aka.ms/powershell>
- Install the Azure CLI on Windows (downloads the MSI installer) — <https://aka.ms/installazurecliwindows>
- Azure MCP Server extension for VS Code — <https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-azure-mcp-server>
- Azure SQL Database resource limits — <https://aka.ms/azuresqlresourcelimits>
- ALTER DATABASE options for Azure SQL Database — <https://learn.microsoft.com/sql/t-sql/statements/alter-database-transact-sql?view=azuresqldb-current>
- ALTER DATABASE SCOPED CONFIGURATION — <https://learn.microsoft.com/sql/t-sql/statements/alter-database-scoped-configuration-transact-sql>
- What's new in Azure SQL Database — <https://aka.ms/whatsnewsqldb>
