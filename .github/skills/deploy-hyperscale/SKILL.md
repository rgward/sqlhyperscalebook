---
name: deploy-hyperscale
description: >-
  Guided, step-by-step deployment of an Azure SQL Hyperscale database for the
  book's Collier Health / Ward General scenario. Interviews the reader one
  decision at a time on the create-time choices (region, globally-unique
  server name, compute size, zone redundancy + HA replica, backup-storage
  redundancy, collation, admin auth), then provisions the database with the
  PowerShell + az CLI script, connects and proves it is SQL Server, builds the
  through-line schema, and seeds synthetic data. USE WHEN the reader says any
  of: "deploy / create / provision / set up / spin up / stand up my (or a)
  Hyperscale database", "get started with Azure SQL Hyperscale", "build the
  Ward General database", "deploy the Chapter 2 database", or "walk me through
  deploying Hyperscale". Scope is deploy + connect + schema + seed ONLY. Do NOT
  use for scaling compute, adding HA / named / geo replicas, point-in-time
  restore, security hardening (Entra-only, CMK, auditing), or teardown /
  cleanup — those are owned by later chapters and their own skills.
---

# Deploy a Hyperscale database (guided)

This skill deploys **one** Azure SQL Hyperscale database and gets it ready to
use, guiding the reader through every decision that matters. It follows the
book's scenario: **Collier Health** is the health *system* (the logical
server, `collierhealth`); **Ward General Hospital** is the flagship hospital
(the Hyperscale database, `wardgeneral`).

**All seed data is synthetic — no real patient data (PHI), ever.**

## Two ways to deploy (same script underneath)

The deploy is a **parameterized, env-var-driven PowerShell script**
(`examples/ch02/provision-hyperscale.ps1`) with sensible defaults for every
value. There are two ways to drive it:

- **Guided (this skill).** Ask Copilot to *"deploy my Hyperscale database"* — it
  runs the interview below one decision at a time, sets each answer as an
  environment variable, validates as it goes, and runs the script at the end.
- **By hand.** Skip the interview: set the variables yourself (each step names
  the one it sets; defaults live in the script) and run it directly. Set
  `SQL_ADMIN_PASSWORD` securely first (see Step 8), then in PowerShell:
  ```powershell
  $env:LOC='eastus2'; $env:RG='rg-collierhealth'; $env:SRV='...'; $env:ADMIN_OBJECT_ID='...'
  ./examples/ch02/provision-hyperscale.ps1
  ```
  You only override what you care about; everything else takes its default. The
  interview simply populates these same variables for you.

## How to run this skill — one decision at a time

**This is a step-by-step interview. Follow it exactly so every prompt and
response is predictable and reproducible** (the book shows each one in order).

Rules for the agent:
- Work through **Steps 1–20 in order**, one at a time. Never batch or skip ahead.
- **Two kinds of step:** a **decision** (has a `Prompt:` — ask the single
  question, then **stop and wait** for the reader's answer) or **informational**
  (*shown, not asked* — state the fact and why in a sentence or two, then
  continue **without** waiting). Present both so the reader sees every choice;
  only stop for decisions.
- **Set each answer live, in the deploy terminal.** As each decision is answered,
  immediately set its environment variable in the **same terminal session**
  (`$env:VAR=...` in PowerShell) — don't defer to the
  end or rely on remembered values. Every step **and** Step 21 run in that **one**
  session, so the deploy uses the reader's actual choices, not the script defaults.
- For steps marked **⚠️ FIXED AT CREATE**, state plainly that it cannot be changed
  later without redeploying (database copy, restore, or geo-replica).
- **Create no Azure resource until Step 21** (the final confirmation). The
  interview only gathers values.
- The reader's **password is entered in the terminal, never in chat** and never
  written to a file.

## The deployment interview

Each step is: *what to tell the reader* → *the prompt* → *the variable it sets*.

### Step 1 — Sign in to Azure, then pick a subscription  → `az account set`
The database gets **billed** to a subscription, but before we can see one we
have to sign in. **Say to the reader (roughly):** *"First we need to know which
Azure subscription to use — so let's log in to Azure first. **Would you like me
to run `az login` now?** If so, you'll switch to the terminal window and handle
the browser pop-up (or device-code prompt) to finish signing in."*
**Wait for the reader's OK before running anything.**

On their OK:
- Run `az login` **in the VS Code integrated terminal**. The reader completes
  the sign-in in the browser pop-up (or the device-code prompt in the terminal).
- **Confirm the active subscription — do NOT dump the full list.** Run
  `az account show --query "{name:name, id:id}" -o table` and ask *"Deploy into
  `<name>`?"* Readers on a corporate tenant can have **hundreds** of
  subscriptions, so listing them all is unusable.
- **Only if they want a different one**, help them find it by name, e.g.
  `az account list --query "[?contains(name,'<search>')].{name:name, id:id}" -o table`,
  then set it with `az account set --subscription <id>`.
- **If there is no subscription at all** after login, they have nothing to deploy
  into — point them to the ways to get one (Visual Studio monthly credits, an
  Azure free account, pay-as-you-go, or Azure for Students; see Chapter 2) and
  **stop here** until they have one.

Prompt: "Deploy into `<active-subscription>` — yes, or name a different one?"

> **Windows note:** run everything in a **PowerShell 7 (pwsh)** integrated
> terminal — `az login`, the interview, and the Step 21 deploy all share that
> one session, so every `$env:` value set along the way is in scope at deploy.

### Step 2 — Permissions (gate, no variable)
Tell: creating a server + database needs **Contributor** or a SQL-specific role
on the subscription/resource group. Confirm they have it; if not, tell them what
to request.

### Step 3 — Region  ⚠️ effectively permanent  → `LOC`
Tell: region is **effectively permanent** (moving later means redeploying), so it
must clear three things for the book's growth arc:
- **Availability-zone support** + **`HS_Gen5` vCore quota**, because we deploy
  **zone-redundant**.
- **Zone-redundant capability** for the chosen shape — verify, don't assume.
- **The eventual scale target.** Later chapters scale to **premium-series, up to
  192 vCores**, and premium-series is **region-restricted**. Since region is
  permanent, confirm the region offers premium-series **now**.

Run these checks for the reader's candidate region:
```powershell
# Current shape available + zone-redundant capable?
az sql db list-editions -l <region> --edition Hyperscale --available `
  --query "[0].supportedServiceLevelObjectives[?name=='HS_Gen5_8'].{slo:name, zoneRedundant:zoneRedundant}" -o table

# Eventual premium-series scale target available (e.g. HS_PRMS_192)?
az sql db list-editions -l <region> --edition Hyperscale --available `
  --query "[0].supportedServiceLevelObjectives[?starts_with(name,'HS_PRMS')].name" -o table
```
Standard-series Gen5 caps at **80 vCores**; premium-series is required beyond
that, so a region with **no `HS_PRMS_*`** can't host the later scale-out.
Prompt: "Which region?"

### Step 4 — Resource group  → `RG`
Tell: a container for the resources; new or existing is fine.
Prompt: "Resource group name? [default `rg-collierhealth`]"

### Step 5 — Logical server name  ⚠️ FIXED AT CREATE  → `SRV`
Tell: globally unique across all of Azure; becomes `<name>.database.windows.net`;
**cannot be renamed**. Offer a `collierhealth-<suffix>` default or take the
reader's name.
**Pre-check global uniqueness with a DNS lookup** — there is no
`az sql server check-name-availability` command, so resolve the FQDN: if it
already resolves, the name is taken (ask for another); NXDOMAIN means it's very
likely free. The definitive check still happens at create.
```powershell
# Resolve-DnsName <name>.database.windows.net   (resolves = taken; NXDOMAIN = likely free)
```
Prompt: "Server name? [default `collierhealth-<suffix>` — I can generate one]"

### Step 6 — Auth model (shown, not asked)
Tell: we use **mixed SQL + Microsoft Entra** auth; a later chapter (Security)
hardens the server to Entra-only.

### Step 7 — SQL admin login  ⚠️ NAME FIXED AT CREATE  → `SQL_ADMIN_USER`
Tell: the SQL admin **login name cannot be changed** after creation.
Prompt: "SQL admin login? [default `wardadmin`]"

### Step 8 — SQL admin password (typed into the terminal, captured securely)  → `SQL_ADMIN_PASSWORD`
The reader **types the password directly into the integrated terminal** — never
into chat, and never inline in an `$env:X='...'` (plaintext would land in terminal
scrollback and shell history). Run the **masked read** so it is
not echoed:
```powershell
# PowerShell (input masked):
$s = Read-Host "SQL admin password" -AsSecureString
Set-Item Env:SQL_ADMIN_PASSWORD (ConvertFrom-SecureString $s -AsPlainText)
```
The agent runs this, then tells the reader to **type their password directly
into the terminal and press Enter**. The **agent never sends, sees, or captures
the value** — the terminal captures it into the env var, and Step 21 runs in the
same PowerShell session so the deploy inherits it.
Requirements: 8+ chars; 3 of {upper, lower, number, symbol}; not the login name.

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

### Step 13 — Edition (shown, not asked)
Tell: **Hyperscale** — that's the whole point of this deployment.

### Step 14 — Shape: single, provisioned (shown, not asked)
Tell: we deploy a **single, provisioned** Hyperscale database. **Elastic pools**
and **serverless** are covered in a later chapter (**Performance, Chapter 10**).

### Step 15 — Compute size  → `SLO`
Tell: the vCore shape; **changeable later** (online scale, Chapter 10).
Prompt: "Compute size? [default `HS_Gen5_8` = 8 vCores]"

### Step 16 — HA replica (shown, not asked)  → `HA_REPLICAS`
Tell: we pre-provision **1 HA replica** — required for zone redundancy, and it
gives faster failover. Changeable later. **Cost note:** each replica bills as
its own compute, so one HA replica ≈ **doubles the compute cost** versus a
primary with no replicas. That's the price of high availability.

### Step 17 — Zone redundancy  ⚠️ FIXED AT CREATE  → `ZONE_REDUNDANT`
Tell: **the single most important permanent choice.** On = survives an
availability-zone failure. Requires ≥1 HA replica (Step 16) and ZRS/GZRS backup
(Step 18). **Cannot be toggled after creation.**
**Cost note:** because zone redundancy requires that HA replica (Step 16), it
carries that replica's compute cost — you cannot have zone redundancy without
paying for at least one replica.
Prompt: "Deploy zone-redundant? [default yes]"

### Step 18 — Backup-storage redundancy  ⚠️ FIXED AT CREATE  → `BACKUP_REDUNDANCY`
Tell: where automated backups are replicated; **set only at create.** In
Hyperscale, data and backups share the **same snapshot storage account**, so
this one choice applies to **both** — that's why it's immutable.

**Cost model (teach it, don't quote dollars):** two *independent* axes.
- **How many GB you store** — kept small by Hyperscale's incremental,
  storage-pushed **snapshots**. Snapshots make backups near-instant, consume no
  compute, and capture only changed pages, so the billable GB count stays low.
- **What each GB costs** — set by the Azure Storage **redundancy tier**, and
  this has nothing to do with snapshots: `Local` (LRS) = `Zone` (ZRS) at the
  **base per-GB rate**; `Geo` (GRS) = `GeoZone` (GZRS) at **≈2× the base rate**,
  because Storage keeps an extra asynchronous copy in the paired region. You're
  paying for a second *geographic* copy of every byte, not for the backup method.
- The two multiply: `bill = (GB, small thanks to snapshots) × (rate, doubled by
  geo)`. Plus the first **one full database size of backup is free**, so only
  the excess is billable:
  `billable = (data backup size + log backup size) − one database size`.
- Net: `GeoZone` buys cross-region durability at ≈2× the storage-redundancy
  rate, but small snapshots + the free allowance keep the actual bill modest
  until the database is large, write-heavy, or on long retention. Point the
  reader at the Azure SQL Database pricing page for current numbers.

**What each choice protects — and what a lesser choice loses** (two axes:
zone-failure protection in-region, and region-failure protection via
*geo-restore* to the paired region):

| Choice | Zone failure | Region failure (geo-restore) | Rate |
| --- | --- | --- | --- |
| `GeoZone` (GZRS) | ✅ protected | ✅ protected | 2× |
| `Geo` (GRS) | ❌ lost | ✅ protected | 2× |
| `Zone` (ZRS) | ✅ protected | ❌ **geo-restore disabled** | 1× |
| `Local` (LRS) | ❌ lost | ❌ lost | 1× |

- Dropping to `Zone` halves the storage-redundancy rate but **disables
  geo-restore** — Learn: *"Geo-restore is disabled as soon as a database is
  updated to use locally redundant or zone-redundant storage."* You'd survive a
  zone failure but **not** the loss of the whole region; regional DR would then
  require **active geo-replication** set up in advance.
- `Geo` costs the same 2× as `GeoZone` but gives up in-region zone resilience —
  when zones are available, `GeoZone` is strictly better at the same price.
- `Local` gives up both; not for production.

**Default: `GeoZone`.** It's the coherent match for the book's zone-redundant
deployment — the compute is already zone-redundant for in-region HA, and
`GeoZone` backups extend that resilience to *regional* disaster recovery.

**Changing it later:** there is **no in-place update on Hyperscale** (unlike
GP/BC, which allow `az sql db update --backup-storage-redundancy`). To change a
Hyperscale database's redundancy you must create a **new** database via **active
geo-replication** (min-downtime) or **database copy** — both size-of-data
operations. That's why this is a decide-at-create choice.

Prompt: "Backup redundancy — Local / Zone / Geo / GeoZone? [default `GeoZone`]"

### Step 19 — Collation  ⚠️ FIXED AT CREATE  → `COLLATION`
Tell: sort and comparison rules for the database; the default suits most
workloads. **It cannot be changed after creation — decide now.**

**Why the default is the popular choice** — `SQL_Latin1_General_CP1_CI_AS`:
- It's the **default** Azure SQL Database assigns when you don't specify one, so
  most databases run it. Tooling, sample databases, and migrations all line up
  with it — no collation-mismatch surprises in joins or `tempdb` comparisons.
- Decoding the name: `SQL_` = a SQL collation (legacy SQL Server sort rules for
  non-Unicode data, kept for back-compat); `Latin1_General` / `CP1` = code page
  1252 (Western European / US-English); `CI` = **case-insensitive**
  (`Smith` = `smith`); `AS` = **accent-sensitive** (`resume` ≠ `résumé`).
- Case-insensitive + accent-sensitive is the least-surprising behavior for
  line-of-business data — users don't expect case to change equality or sort.

**When a reader would choose differently:** a globalized, Unicode-heavy app may
prefer a *Windows* collation such as `Latin1_General_100_CI_AS_SC_UTF8` — `_SC`
adds supplementary-character (full Unicode) support and `_UTF8` enables UTF-8
storage. For the book's scenario the default is the right call: maximally
compatible and least surprising.

Prompt: "Collation? [default `SQL_Latin1_General_CP1_CI_AS`]"

### Step 20 — Resource tags  → `TAGS`
Tell: tags are `key=value` metadata for **governance, cost allocation, and
incident response**. Azure's Cloud Adoption Framework groups them into
**functional / classification / accounting / ownership** categories, and most
orgs enforce a minimal set with Azure Policy. Tags are changeable later, but set
them now so the resources are governed from birth. The script applies the **same
tag set to the resource group, logical server, and database**.
Recommended minimal set (CAF-aligned) — offer these defaults; let the reader edit.
This Ch 2 deploy is a **follow-along test database**, so tags state what it IS now
(a sandbox with synthetic data). In the scale chapter it is **promoted** —
`environment=prod`, `criticality=mission-critical`, `dataClassification=confidential`
(and in real life you'd stand up a *separate* prod instance, not relabel this one).
- `environment` = `sandbox` (real options `dev` | `test` | `prod`)
- `application` = `ward-general-ehr` (the workload this database serves)
- `owner` = the team/principal accountable (defaults to the Entra admin)
- `criticality` = `low` (a sandbox, not a live EHR)
- `dataClassification` = `nonproduction` (the seed is synthetic / no PHI)
- `costCenter` = the chargeback code (**no sensible default — ask if they want it**)
Spaces aren't allowed in a tag passed on the command line — hyphenate values.
Prompt: "Tags? Press Enter to accept the recommended set, or give
`key=value` pairs (space-separated) to override."

## Step 21 — Confirm and deploy

Echo **every** choice back in a summary (region, RG, server, database, size, HA,
zone redundancy, backup redundancy, collation, tags, auth, firewall). Remind the reader
this creates **real, billable** resources. On explicit confirmation, run:

```powershell
# All decisions are already set as $env:* in this session (Steps 1–20),
# including $env:SQL_ADMIN_PASSWORD from Step 8. Run the script:
./examples/ch02/provision-hyperscale.ps1
```

(Every value comes from the `$env:*` variables set live during the interview; the
script falls back to its own defaults for anything not set.)

## After the deploy

### Verify the provision
- Resource group and logical server exist; the server has **mixed (SQL + Entra)
  auth**.
- `wardgeneral` shows `Edition = Hyperscale`, the chosen `ServiceObjective`,
  `highAvailabilityReplicaCount = 1`, `zoneRedundant = <chosen>`, and
  `requestedBackupStorageRedundancy = <chosen>`.

### Connect and prove it's SQL Server (`examples/ch02/connect-and-verify.sql`)
**Guide the reader through this — do NOT do it for them.** Connecting the book's
primary client (the MSSQL extension) with Microsoft Entra auth is a hands-on
moment the reader performs themselves; the agent **instructs and confirms**, it
does not connect or run the queries. (The extension's `connect` tool can't create
that first Entra-authenticated connection anyway — only the reader's UI action can.)

**Give the reader the exact connection details from the deploy** — fill these in
from the interview values / `az sql db show`; never leave placeholders:
- **Server / hostname:** `<SRV>.database.windows.net` (the globally-unique server
  name from Step 5, i.e. `collierhealth-<suffix>.database.windows.net`)
- **Database:** `<DB>` (the database from Step 12, i.e. `wardgeneral`)
- **Authentication:** **Microsoft Entra** (Entra ID — Universal with MFA); the
  signed-in user is the server's Entra admin, so **no SQL login or password**.
- **Encryption / port:** Encrypt = true, 1433 (the extension's defaults).

Tell the reader to:
1. In the **MSSQL extension**, choose **Add Connection**, paste the **server
   hostname** above, pick **Microsoft Entra** authentication (expect an MFA
   browser / device-code prompt), and select database `<DB>`.
2. Open `examples/ch02/connect-and-verify.sql` and run it against that connection.

Then have them confirm the four checks — the *"prove it's SQL Server, prove it's
Hyperscale"* payoff Ch 1 §6 points to:
- **`@@VERSION`** → a *Microsoft SQL Azure* build string (it really is SQL Server).
- **Edition / ServiceObjective** → `Edition = Hyperscale`, `ServiceObjective`
  starts with `HS_` (e.g. `HS_Gen5_8`); `Updateability = READ_WRITE` on the primary.
- **Resource limits** (`sys.dm_user_db_resource_governance`) → the SLO's CPU,
  worker-thread, and **primary max log rate** (the Ch 10 write ceiling) in effect.
- **Replica role** → the primary reports `READ_WRITE` (an HA / named replica is `READ_ONLY`).

(Schema/table verification is **not** here — it lives in `verify-data.sql`, run
after the schema build.)

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
| `provision-hyperscale.ps1` | canonical CLI provision (Step 21) |
| `connect-and-verify.sql` | prove-it's-SQL-Server |
| `01-schemas.sql` | §3 `CREATE SCHEMA clinical / ops` |
| `02-tables.sql` | §3 13 tables + indexes + bedside invariant |
| `03-views.sql` | §3 `vPatientChart` + per-section views |
| `04-procedures.sql` | §3 admit / discharge / record-vitals / read-chart |
| `05-seed.sql` | §3 synthetic seed (~10 GB) |
| `verify-data.sql` | post-seed row-count + reserved-size check |
