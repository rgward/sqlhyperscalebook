---
name: deploy-hyperscale
description: >-
  Guided deployment of an Azure SQL Hyperscale database for the book's
  Collier Health / Ward General scenario. Interviews the reader on the key
  create-time decisions (region, globally-unique server name, compute size,
  zone redundancy + HA replica, backup-storage redundancy, admin auth),
  then provisions the database, connects and proves it is SQL Server, builds
  the through-line schema, and seeds a reasonable amount of synthetic data.
  USE WHEN the reader says: "deploy my Hyperscale database", "set up
  Hyperscale", "get started with Azure SQL Hyperscale", "provision a
  Hyperscale database", "build the Ward General database", "walk me through
  deploying Hyperscale". Scope is deploy + connect + schema + seed only;
  scaling, replicas, restore and teardown are covered by later chapters.
---

# Deploy a Hyperscale database (guided)

This skill deploys **one** Azure SQL Hyperscale database and gets it ready to
use, guiding the reader through every decision that matters. It follows the
book's scenario: **Collier Health** is the health *system* (the logical
server, `collierhealth`); **Ward General Hospital** is the flagship hospital
(the Hyperscale database, `wardgeneral`).

**All seed data is synthetic — no real patient data (PHI), ever.**

## How to run this skill — one decision at a time

**This is a step-by-step interview. Follow it exactly so every prompt and
response is predictable and reproducible** (the book shows each one in order).

Rules for the agent:
- Work through **Steps 1–19 in order**. Present **one decision at a time**: give
  the short explanation, ask the single question, then **stop and wait** for the
  reader's answer. Never batch questions or skip ahead.
- Record each answer as the environment variable named in the step.
- For steps marked **⚠️ FIXED AT CREATE**, state plainly that it cannot be changed
  later without redeploying (database copy, restore, or geo-replica).
- **Create no Azure resource until Step 20** (the final confirmation). The
  interview only gathers values.
- The reader's **password is entered in the terminal, never in chat** and never
  written to a file.

## The deployment interview

Each step is: *what to tell the reader* → *the prompt* → *the variable it sets*.

### Step 1 — Azure subscription
Tell: this subscription is what gets billed; confirm the right one if they have
several. Prompt: "Which subscription should I deploy into?" (show
`az account show`). Sets the active subscription (`az account set`).

### Step 2 — Permissions (gate, no variable)
Tell: creating a server + database needs **Contributor** or a SQL-specific role
on the subscription/resource group. Confirm they have it; if not, tell them what
to request.

### Step 3 — Region  → `LOC`
Tell: the region must have **availability-zone support** and **`HS_Gen5` vCore
quota**, because we deploy **zone-redundant**. *(Effectively permanent — moving
means redeploying.)* Offer to run the capacity check
(`az sql db list-editions --edition Hyperscale --available`). Prompt: "Which
region?"

### Step 4 — Resource group  → `RG`
Tell: a container for the resources; new or existing is fine.
Prompt: "Resource group name? [default `rg-collierhealth`]"

### Step 5 — Logical server name  ⚠️ FIXED AT CREATE  → `SRV`
Tell: globally unique; becomes `<name>.database.windows.net`; **cannot be
renamed**. Prompt: "Server name? [default `collierhealth-<suffix>` — I can
generate one]"

### Step 6 — Auth model (tell, not asked)
Tell: we use **mixed SQL + Microsoft Entra** auth; a later chapter (Security)
hardens the server to Entra-only.

### Step 7 — SQL admin login  ⚠️ NAME FIXED AT CREATE  → `SQL_ADMIN_USER`
Tell: the SQL admin **login name cannot be changed** after creation.
Prompt: "SQL admin login? [default `wardadmin`]"

### Step 8 — SQL admin password (terminal only)  → `SQL_ADMIN_PASSWORD`
Tell: strong password; **type it into the terminal**, not into chat; it is never
saved to a file. Have them set it in the terminal
(`export SQL_ADMIN_PASSWORD=<your-password>`).

### Step 9 — Entra admin  → `ADMIN_TYPE`, `ADMIN_DISPLAY_NAME`, `ADMIN_OBJECT_ID`
Tell: the Microsoft Entra principal that will also be a server admin.
Prompt: "Entra admin — User, Group, or ServicePrincipal? Its display name? Its
object id?"

### Step 10 — Allow Azure services firewall rule  → `ALLOW_AZURE_SERVICES`
Tell: this `0.0.0.0` rule lets **other Azure services** (Foundry, MCP servers,
Functions) reach the server — **handy in dev/test** for the book's later
chapters, but it is **broad exposure**; **disable it for production.**
Prompt: "Enable 'Allow Azure services' for now? (yes for dev/test — you can
remove it later) [yes/no]"

### Step 11 — Your client IP (firewall)
Tell: needed so **you** can connect from this machine. Auto-detect
(`curl -s https://ifconfig.me`), show it, and confirm before adding the rule.

### Step 12 — Database name  ⚠️ FIXED AT CREATE  → `DB`
Tell: **cannot be renamed** (rename = redeploy).
Prompt: "Database name? [default `wardgeneral`]"

### Step 13 — Edition (tell, not asked)
Tell: **Hyperscale** — that's the whole point of this deployment.

### Step 14 — Shape: single, provisioned (tell, not asked)
Tell: we deploy a **single, provisioned** Hyperscale database. **Elastic pools**
and **serverless** are covered in a later chapter (**Performance, Chapter 10**).

### Step 15 — Compute size  → `SLO`
Tell: the vCore shape; **changeable later** (online scale, Chapter 10).
Prompt: "Compute size? [default `HS_Gen5_8` = 8 vCores]"

### Step 16 — HA replica (tell, not asked)  → `HA_REPLICAS`
Tell: we pre-provision **1 HA replica** — required for zone redundancy, and it
gives faster failover. Changeable later.

### Step 17 — Zone redundancy  ⚠️ FIXED AT CREATE  → `ZONE_REDUNDANT`
Tell: **the single most important permanent choice.** On = survives an
availability-zone failure. Requires ≥1 HA replica (Step 16) and ZRS/GZRS backup
(Step 18). **Cannot be toggled after creation.**
Prompt: "Deploy zone-redundant? [default yes]"

### Step 18 — Backup-storage redundancy  ⚠️ FIXED AT CREATE  → `BACKUP_REDUNDANCY`
Tell: where automated backups are replicated; **set only at create.**
Prompt: "Backup redundancy — Local / Zone / Geo / GeoZone? [default `GeoZone`]"

### Step 19 — Collation  ⚠️ FIXED AT CREATE  → `COLLATION`
Tell: sort/comparison rules for the database; the default suits most workloads.
**It cannot be changed after creation — decide now.**
Prompt: "Collation? [default `SQL_Latin1_General_CP1_CI_AS`]"

## Step 20 — Confirm and deploy

Echo **every** choice back in a summary (region, RG, server, database, size, HA,
zone redundancy, backup redundancy, collation, auth, firewall). Remind the reader
this creates **real, billable** resources. On explicit confirmation, run:

```bash
LOC=... RG=... SRV=... DB=... \
ADMIN_TYPE=... ADMIN_DISPLAY_NAME="..." ADMIN_OBJECT_ID=... \
SQL_ADMIN_USER=... SLO=... ZONE_REDUNDANT=... BACKUP_REDUNDANCY=... \
COLLATION="..." ALLOW_AZURE_SERVICES=... \
bash examples/ch02/provision-hyperscale.azcli
```

(`SQL_ADMIN_PASSWORD` is already exported in the terminal from Step 8.)

## After the deploy

### Verify the provision
- Resource group and logical server exist; the server has **mixed (SQL + Entra)
  auth**.
- `wardgeneral` shows `Edition = Hyperscale`, the chosen `ServiceObjective`,
  `highAvailabilityReplicaCount = 1`, `zoneRedundant = <chosen>`, and
  `requestedBackupStorageRedundancy = <chosen>`.

### Connect and prove it's SQL Server (`examples/ch02/connect-and-verify.sql`)
Use the MSSQL extension's `connect` tool to register the database, then run the
verification queries.
- `@@VERSION` returns a Microsoft SQL Azure build string.
- `DATABASEPROPERTYEX(DB_NAME(),'Edition') = Hyperscale`.
- `DATABASEPROPERTYEX(DB_NAME(),'ServiceObjective')` starts with `HS_`.
- The schema-sanity query returns the expected base tables.

### Build the schema and seed (`examples/ch02/01-schemas.sql` → `05-seed.sql`)
Two schemas, 13 tables, the digital-patient-chart views, foundational
procedures, and a reproducible synthetic seed (no real PHI).

```
01-schemas.sql    -- create schema clinical; create schema ops;
02-tables.sql     -- 13 tables, FKs, filtered unique index for active beds
03-views.sql      -- clinical.vPatientChart + per-section views
04-procedures.sql -- GetPatientChart / AdmitPatient / DischargePatient / RecordVitals
05-seed.sql       -- ~10 GB of synthetic data
```

- The schema-sanity query lists 13 tables across `clinical.*` and `ops.*`.
- Row counts from `05-seed.sql` match the documented volumes (within a few
  percent). Reserved space is "a little over 10 GB." Seed runtime on
  `HS_Gen5_8` is a few minutes (log-rate gated); lower the per-batch scale
  factor at the top of `05-seed.sql` for a smoke test.

## Scope discipline

This skill deploys and prepares the database — nothing more. It does **not**
scale compute, add HA or named replicas, run a point-in-time restore, or tear
anything down; those are covered by later chapters. If the reader asks "why?"
on any step, answer in one sentence and keep moving.

## Files this skill runs

All under `examples/ch02/`:

| File | Role |
|---|---|
| `provision-hyperscale.azcli` | canonical CLI provision (Step 20) |
| `connect-and-verify.sql` | prove-it's-SQL-Server |
| `01-schemas.sql` | §3 `CREATE SCHEMA clinical / ops` |
| `02-tables.sql` | §3 13 tables + indexes + bedside invariant |
| `03-views.sql` | §3 `vPatientChart` + per-section views |
| `04-procedures.sql` | §3 admit / discharge / record-vitals / read-chart |
| `05-seed.sql` | §3 synthetic seed (~10 GB) |
| `verify-data.sql` | post-seed row-count + reserved-size check |
