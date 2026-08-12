---
name: wardgeneral-app
description: >-
  Build, run, restart and stop the Ward General Blazor web application and its
  data-access library against an Azure SQL Hyperscale database — the Chapter 4
  example from *Azure SQL Hyperscale Unveiled*. USE WHEN the reader says any of:
  "build the app", "run the app", "restart the app", "stop the app", "restart the
  app with a feature flag", "flip a feature flag", "build the Ward General app",
  "run the Ward General app", "Run Ward General Hospital app", "start the Ward
  General Hospital app", "start the hospital app", "get the chart app running",
  "build the Chapter 4 app", or wants to point the app at the wardgeneral
  Hyperscale database and see the patient chart in a browser. Covers: the example
  layout, configuring the passwordless (Microsoft Entra) connection, building with
  build.ps1, running with run.ps1, restarting with restart.ps1 -Enable to pick up
  a feature flag, stopping with shutdown.ps1, and what each screen shows. Scope is
  BUILD + CONFIGURE + RUN the app ONLY. Do NOT use to deploy the database (see
  deploy-hyperscale), deploy the Azure AI resources a feature flag depends on (see
  deploy-wardgeneral-ai), stand up DAB / the SQL MCP server, or provision Azure App
  Service / Container Apps.
---

# Build and run the Ward General app

A small, real line-of-business web app: a hospital **patient chart** over an
Azure SQL Hyperscale database (`wardgeneral`). It is deliberately boring on the
surface so the interesting part is visible — **how a developer app talks to
Hyperscale**: passwordless auth, stored-proc data access, native `json`, and
app-side resiliency.

All paths below are workspace-relative to the repo root. The example lives in
`examples/ch04-first-app/` and is the Chapter 4 application.

**All data is synthetic — no real patient data (PHI), ever.**

> **Where it runs.** The app runs **locally** (Kestrel on `https://localhost:7170`)
> so it is trivial to build and run on any laptop while reading. In reality it belongs
> in **Azure App Service** (or a Container App) — ideally with VNet
> integration so it reaches the database over the private endpoint. The database,
> managed-identity auth, RLS, and Private Link all live in Azure regardless of where the
> app runs; only this web process is local.

## What's in the example

```
examples/ch04-first-app/
  src/
    WardGeneral.Data/     class library — the data-access layer (reused everywhere)
      WardGeneralConnectionFactory.cs   Entra auth, no secrets  (Secure it)
      RetryPolicy.cs                    transient-fault retry   (Make it HA)
      ChartRepository.cs                calls the stored procs + reads vBedCensus
      Models/ChartModels.cs             typed models for the json chart sections
    WardGeneral.Web/      Blazor Web App (Interactive Server) → references WardGeneral.Data
      Components/Pages/Home.razor        Unit board (ops.vBedCensus)
      Components/Pages/Chart.razor       the bedside patient chart
      appsettings.json                   shape only — Server ships EMPTY on purpose
      appsettings.Development.json       git-ignored: YOUR server / database go here
  WardGeneral.slnx        solution (both projects)
  build.ps1               builds the solution
  run.ps1                 runs the app and opens your default browser
  restart.ps1             stops it, then runs it again (use after a config change)
  shutdown.ps1            backstop: frees 7170 / 5170 if the terminal was closed
  preflight-build.ps1     SDK check, called by build.ps1
  preflight-run.ps1       sign-in / firewall / database check, called by run.ps1
```

The **SQL lives with the chapter that teaches it**, not in this folder: schema +
seed in `examples/ch02-getting-started/`, embeddings and AI assistance in
`examples/ch05-ai-ready-sql/`, DAB / MCP and the AI gateway in
`examples/ch06-agentic-ai/`, Row-Level
Security in `examples/ch08/`.

The web app references the DAL library (it compiles into the app's output — one
deployable unit), so the same DAL can be reused elsewhere. Every database call
goes through a **stored procedure** (the Unit board reads `ops.vBedCensus`
directly); there is no ad-hoc write SQL and no ORM, so the path stays visible.

## Prerequisites (verify, don't assume)

- **.NET 10 SDK** — `dotnet --list-sdks` must show a `10.x` SDK.
- **PowerShell 7+ (`pwsh`)** — to run `build.ps1` / `run.ps1`.
- **A deployed Hyperscale database** with the schema + seed loaded. If it isn't
  deployed yet, deploy the scripts in
  `examples/ch02-getting-started/` (`01-schemas.sql` →
  `05-seed.sql`).
- **A Microsoft Entra identity with access to the database.** Locally the app
  uses `Active Directory Default`, which picks up your **`az login`** / Visual
  Studio / VS Code sign-in. Confirm with `az account show`.

There is **no password anywhere** in this app or its config — that's the point.

## Steps

### 1 — Point the app at your database

**ASK the reader for their logical server name before doing anything else.** The
committed `appsettings.json` ships with `"Server": ""` — no live server name is
ever a committed default — so this step is mandatory, not optional. Don't guess a
name and don't reuse one from another chapter's output.

If they don't know it, offer to find it:
```powershell
az sql server list -o table
```

Then write it to the **git-ignored** local overlay,
`examples/ch04-first-app/src/WardGeneral.Web/appsettings.Development.json`:
```json
{
  "WardGeneral": {
    "Server": "<your-server>.database.windows.net",
    "Database": "wardgeneral"
  }
}
```

ASP.NET Core layers three sources, highest wins — explain this once, because it is
the reusable pattern, not a Ward General quirk:

| Layer | Where | Use it for |
|---|---|---|
| 1. `appsettings.json` | committed | the **shape**, and only values that are true everywhere (`Database`, `Deployment`) |
| 2. `appsettings.Development.json` | git-ignored | **your** environment — server name, AI endpoint |
| 3. `WardGeneral__Server` env var | shell | one-off overrides; `run.ps1 -Server` sets exactly this |

So `./run.ps1 -Server <your-server>.database.windows.net` works with no file edit
at all — offer that if the reader just wants to try it once.

None of these is a secret: there is no password, and the connection uses the
reader's Entra sign-in. They are *environment* values, kept out of the commit so
nobody inherits someone else's server.

If `Server` is still blank, the app **fails at startup** with a message naming
all three options — by design. That is not a bug to work around.

The Azure OpenAI endpoint (`Agent:Endpoint`) is blank for the same reason, but a
Chapter 4 reader never needs it — it belongs to the `Assistant` flag (Chapter 6,
see `deploy-wardgeneral-ai`).

### 2 — Sign in (passwordless auth)
```powershell
az login   # or sign in to Visual Studio / VS Code with an identity that has DB access
```

### 3 — Build
```powershell
./examples/ch04-first-app/build.ps1
# -Configuration Release, or -Publish to dotnet publish the web app
```

### 4 — Run (and open the browser)
```powershell
./examples/ch04-first-app/run.ps1
#   -OpenOnly   just open the browser (app already running)
#   -NoBrowser  start without opening
```
Opens your **default** browser at `https://localhost:7170`. If a dev-cert
warning appears, proceed (it's your machine); one-time fix: `dotnet dev-certs https --trust`.

> Do NOT use the VS Code Simple Browser — it rejects the dev cert and drops the
> Blazor circuit. `run.ps1` launches your real browser via `Start-Process`.

### 5 — Turn on the optional panels (later chapters)
Everything a later chapter teaches ships **off**, because the SQL behind it is
deployed by that chapter and an empty panel is worse than no panel. Turn one on
and restart:
```powershell
./examples/ch04-first-app/restart.ps1 -Enable AiAssistance              # Ch 5 · AI assistance card
./examples/ch04-first-app/restart.ps1 -Enable Assistant                 # Ch 6 · assistant dock (needs DAB)
./examples/ch04-first-app/restart.ps1 -Enable RowLevelSecurity          # Ch 8 · "Viewing as" + RLS filtering
./examples/ch04-first-app/restart.ps1 -Enable AiAssistance,Assistant    # more than one
./examples/ch04-first-app/restart.ps1                                   # back to defaults
```
The backing SQL: `AiAssistance` needs `06-ai-embeddings.sql` +
`07-ai-assistance.sql` from `examples/ch05-ai-ready-sql/`; `Assistant` needs DAB
running (`examples/ch06-agentic-ai/setup-dab.ps1`, then `run-dab.ps1`);
`RowLevelSecurity` needs the Chapter 8 security policy deployed.

A **restart is required** — the flags bind as `IOptions<FeatureFlags>`, resolved
once at startup, so a page refresh does nothing. No rebuild: `run.ps1` uses
`dotnet run`, which reads `appsettings.json` from the project directory.

Use `restart.ps1`, not `run.ps1`, for this. `run.ps1` sees the old process still
listening on 7170 and just opens the browser at it — the flag looks broken when
it is actually fine.

**Chapter 4 features are not flags.** The base chart — including the *From the
note* card, where `REGEXP_*` extracts vitals in-engine — is simply part of the
app. It self-hides only if `clinical.vChartNoteSignals` hasn't been deployed.

## What you should see

- **Unit board (home).** A **unit selector** + Occupied/all toggle, then a grid of
  **bed cards** from `ops.vBedCensus`: bed · patient · MRN · attending · admitted.
  Click an occupied bed → the chart. You navigate by room/patient, never by
  encounter. With `RowLevelSecurity` enabled (Chapter 8, step 5) a **Viewing as**
  selector also appears: it defaults to **Admin — all patients**; pick an
  attending and the engine filters the board (and the charts) to that clinician's
  patients via `SESSION_CONTEXT`, no restart.
- **Bedside chart (`/chart/{id}`).** Room/Bed header, allergy alert banner,
  computed alerts + vitals grid (abnormal values flagged), care team, symptoms,
  medications, imaging, labs, and recent clinical notes — the chart's sections
  come back as native `json`. A **From the note** card shows values mined from the
  latest note text in-engine with `REGEXP_*` (BP · HR · temp · pain · follow-up).
  Under the alerts strip is an **AI assistance** card
  (advisory, on-demand, **off unless you enable it** — see step 5): click *Get AI assistance* to call
  `clinical.GenerateClinicalAssistance` — a *suggested* triage flag (the attending
  confirms/overrides) + a grounded summary + the note ids it used (vector search +
  gpt-5, in-engine, audited).

## How the code maps to the book

- **Passwordless auth (Chapter 8)** — `WardGeneralConnectionFactory` uses
  `ActiveDirectoryDefault`
  (managed identity in Azure, your dev sign-in locally). No login, no password.
  The same one identity + **Row-Level Security** (off until step 5): the **Viewing
  as** selector writes the acting clinician into `SESSION_CONTEXT` (per-circuit
  `AccessContext`), and `security.EncounterAccessPolicy` on `clinical.Encounter`
  filters rows in the engine — the trusted-subsystem pattern. See
  `examples/ch08/10-row-level-security.sql`.
- **Resiliency and read scale-out (Chapter 9)** — `RetryPolicy` retries transient
  faults; reads pass `ApplicationIntent=ReadOnly` to reach a secondary replica.
- **Native `json` (Chapter 5)** — the chart's sections come back as native `json`,
  parsed into typed models in `ChartModels.cs`.
- **In-engine `REGEXP_*` (Chapter 4)** — the *From the note* card mines values out
  of note text in the engine rather than in C#.

## Troubleshooting

- **Auth / login errors** — `az login` (or sign in to VS/VS Code) with an
  identity that has DB access; confirm with `az account show`.
- **"WardGeneral:Server is not configured"** — expected on a fresh clone;
  `appsettings.json` ships blank. Do step 1.
- **"No such host is known"** — the server name is wrong. Check
  `appsettings.Development.json` (or `$env:WardGeneral__Server`) against
  `az sql server list -o table`.
- **HSTS / blank page on http://** — a prior HTTPS run cached HSTS for localhost.
  `run.ps1` serves both HTTP and HTTPS to handle this; use the HTTPS URL.
- **App runs but no beds/patients** — the schema/seed isn't loaded. Deploy
  `examples/ch02-getting-started/01-schemas.sql` → `05-seed.sql`, then
  `verify-data.sql` in the same folder.
- **Flipped a feature flag and nothing changed** — you probably re-ran `run.ps1`,
  which found the old process on 7170 and opened the browser at it instead of
  starting a new one. Use `restart.ps1 -Enable <flag>`.
- **Build fails on the SDK** — confirm a .NET 10 SDK (`dotnet --list-sdks`).
