# Chapter 2 — Getting Started

Provision an Azure SQL **Hyperscale** database, connect to it, build the
through-line schema, and seed it with fully synthetic data. This is the database
every later chapter builds on: the **Ward General Hospital** database
(`wardgeneral`) on the **Collier Health** logical server (`collierhealth`).

> **New here?** Read the [repository README](../../README.md) first — it covers the
> scenario, prerequisites (VS Code, GitHub Copilot, PowerShell 7, Azure CLI, the
> MSSQL extension, an Azure subscription), and how to run the guided deploy with
> the `deploy-hyperscale` Copilot skill.

## The flow

Four moves, in order:

1. **Deploy** — create the logical server + Hyperscale database (`provision-hyperscale.ps1`).
2. **Connect & prove it's SQL Server** — run `connect-and-verify.sql`.
3. **Build the schema** — run `01`→`04` in order.
4. **Seed & verify** — run `05-seed.sql`, then `verify-data.sql`.

You can drive all of this through Copilot (ask it to *"deploy my Hyperscale
database"* and it runs the `deploy-hyperscale` skill), or run the scripts by hand
as described below.

> **Tip — a third way to verify.** After the deploy, run
> `verify-activity-log.ps1` for a control-plane check: it summarizes the Azure
> Activity Log (every operation that built the database) and flags any failures.
> That's the deploy proof; `connect-and-verify.sql` is the tier proof and
> `verify-data.sql` is the data proof — same database, three angles.

## Files in this folder

| File | Type | What it does |
|---|---|---|
| `provision-hyperscale.ps1` | PowerShell | Creates `rg-collierhealth`, the `collierhealth` logical server, and the `wardgeneral` Hyperscale database in one `az sql db create` — provisioned, single, **1 HA replica, zone-redundant, GeoZone backup**. Mixed SQL + Entra auth. Calls `estimate-cost.ps1` at the end. |
| `estimate-cost.ps1` | PowerShell | Prints a live, itemized monthly cost estimate for the deployed shape from the public Azure Retail Prices API, plus the deploy-time cost-vs-resilience levers (drop the HA replica / zone redundancy ≈ −50% compute; Zone vs GeoZone backup). No dollar figures are hard-coded. |
| `verify-activity-log.ps1` | PowerShell | Read-only control-plane check: summarizes the Azure **Activity Log** for `rg-collierhealth` (every operation ARM ran to build the database) — events by status, by operation, most-recent table, and a **failure flag**. A clean deploy shows all `Succeeded`. Widen the window with `$env:OFFSET='1d'` (default 6h). |
| `connect-and-verify.sql` | SQL | Proves it's SQL Server: `@@VERSION`, `DATABASEPROPERTYEX`, service objective, and the governing limits (workers, sessions, log rate, IOPS, memory, 128 TB ceiling, collation, compatibility level) in human units. |
| `01-schemas.sql` | SQL | Creates the `clinical` and `ops` schemas. |
| `02-tables.sql` | SQL | Creates all 13 tables — clustered keys, FKs, constraints, and the three native `json` columns. |
| `03-views.sql` | SQL | Creates `clinical.vPatientChart` and its supporting chart views. |
| `04-procedures.sql` | SQL | Creates the read/write procedures (admit, discharge, record vitals, place order, file lab, add note/diagnosis/allergy, `SearchEncounters`, chart reads). The app, DAB, and the agent all call these — not ad-hoc SQL. |
| `05-seed.sql` | SQL | Seeds ~10 GB of fully synthetic data (Observation is the ~108M-row anchor). Runs ~5–15 min — log-rate gated. |
| `verify-data.sql` | SQL | Read-only PASS/FAIL check with per-table volume checks. You want it to end with **`ALL CHECKS PASSED`**. |

## Deploy inputs (environment variables)

`provision-hyperscale.ps1` reads its inputs from environment variables, each with
a sensible default. Set any overrides **before** running it (the
`deploy-hyperscale` skill sets these for you during the guided deploy):

| Variable | Default | Notes |
|---|---|---|
| `LOC` | `eastus2` | Region — pick one with availability-zone support and `HS_Gen5` quota. |
| `RG` | `rg-collierhealth` | Resource group. |
| `SRV` | `collierhealth-<random>` | Logical server — must be globally unique. |
| `DB` | `wardgeneral` | The Hyperscale database. |
| `SLO` | `HS_Gen5_8` | Compute shape — changeable later. |
| `HA_REPLICAS` | `1` | Required for zone redundancy. |
| `ADMIN_OBJECT_ID` | *(required)* | Entra object ID for the server's Entra admin. |
| `ADMIN_DISPLAY_NAME` | `Collier Health DBAs` | Entra admin display name. |
| `ADMIN_TYPE` | `Group` | `User` \| `Group` \| `ServicePrincipal`. |
| `SQL_ADMIN_USER` | `wardadmin` | Mixed-auth SQL admin login (Ch 8 moves to Entra-only). |
| `SQL_ADMIN_PASSWORD` | *(required)* | Set in the environment — never hard-coded. |

## Running the SQL scripts (and re-running them)

Run `01`→`05` **in order once**, then `verify-data.sql`. **You never drop the
database to start over:**

- **Reload just the data** → re-run `05-seed.sql` alone (truncate + reseed).
- **Rebuild after a schema change** → re-run `02`→`05` (`02` drops and recreates
  the tables, discarding data).
- `01` is a guarded no-op; `03`/`04` are `CREATE OR ALTER` (safe anytime).

Every `.sql` file opens with the seven-line `SET`-options preamble so the scripts
behave identically in the MSSQL extension, SSMS, or `sqlcmd`. See the
[repository README](../../README.md) for the full re-run and `SET`-options
explanation.

## A note on the data

**All data is synthetic. There is no real patient data (PHI) here — ever.** The
dataset was generated with AI assistance and, while plausible, may not accurately
represent real medical, clinical, laboratory, or billing data. It is for
educational and illustrative purposes only and must not be used for clinical,
diagnostic, or any real-world healthcare decision-making.
