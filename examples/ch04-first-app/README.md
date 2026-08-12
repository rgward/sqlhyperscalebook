# Chapter 4 — Your First App

Build a real application on the database you provisioned in Chapter 2. **Ward
General Hospital** is a bedside chart: a unit board of occupied beds, a patient
chart assembled from one round trip, vitals and note entry, and an in-engine
`REGEXP_*` note-signal card. It is an ASP.NET Core **Blazor** app on **.NET 10**
talking to `wardgeneral` over **raw ADO.NET** — no ORM — with a **passwordless**
Microsoft Entra connection.

> **New here?** Read the [repository README](../../README.md) first — it covers
> the scenario and prerequisites. This chapter assumes `wardgeneral` already
> exists with its schema and seed data (see
> [Chapter 2](../ch02-getting-started/README.md)).

This is the only example folder with a **build** step. Everything else in the
book is SQL or PowerShell.

## Requirements

Everything below is for building and running the Chapter 4 app itself. The
locked surfaces need more — an Azure OpenAI deployment for Chapter 5, Data API
Builder for Chapter 6 — but none of that is required here. The table in the
next section names what each one wants when you get to it.

**To build:**

| Requirement | Why |
|---|---|
| **.NET 10 SDK** or later | All three projects target `net10.0`. An older SDK fails with `NETSDK1045`, which reads like a project error rather than a missing install. Check with `dotnet --list-sdks`. |
| **PowerShell 7** | Every script here opens with `#requires -Version 7.0`. Windows PowerShell 5.1 will not run them. |
| A trusted **HTTPS developer certificate** | `dotnet dev-certs https --trust`. Without it the browser rejects the certificate and drops the Blazor circuit, which looks like an app bug. |

Nothing in the build touches Azure. You can compile the solution on a machine
with no sign-in and no database.

**To run:**

| Requirement | Why |
|---|---|
| **Azure CLI**, signed in with `az login` | The connection uses `ActiveDirectoryDefault`, and `DefaultAzureCredential` resolves that same sign-in. There is no password. |
| An identity that can reach the database | The app connects as **you**, not as a service account. Chapter 2 makes you the server's Entra admin, which is enough. |
| **`wardgeneral` with the Chapter 2 schema *and* its seed data** | Schema without seed gives you a working app with empty screens — a confusing place to land. |
| A **firewall rule** for this client's IP on the logical server | Otherwise the first data load times out. |
| Ports **7170** and **5170** free | Kestrel binds both. `shutdown.ps1` frees them. |
| A real browser | Not the VS Code Simple Browser — see the note under *Running it*. |

You do not have to check these by hand. `build.ps1` runs `preflight-build.ps1`
and `run.ps1` runs `preflight-run.ps1`, which verify all of it — including
counting patients to prove the seed ran — and name the fix for anything
missing. Run either on its own the first time you sit down with the code.

## What this is — and isn't

The app is the book's through-line. It is written **once, here**, and never
gains per-chapter code deltas. Later chapters change the *database* — a new
proc, a new index, a security predicate — and the reader flips a **feature
flag**. Nothing in `src/` is edited again.

Which is why the app you run in Chapter 4 already contains surfaces you cannot
use yet. They are **greyed out, not hidden**: you can see what the app becomes
and which chapter gets you there.

| Surface | Flag | Unlocks in | Needs |
|---|---|---|---|
| **Research** page (sidebar) and the chart's **AI assistance** card | `Features:AiAssistance` | Chapter 5 | `06-ai-embeddings.sql`, `07-ai-assistance.sql`, `08-research-vector-search.sql` from [`examples/ch05-ai-ready-sql/`](../ch05-ai-ready-sql/) |
| **Chat icon** — the clinical assistant dock | `Features:AiAgent` | Chapter 6 | DAB running: `setup-dab.ps1` then `run-dab.ps1` in [`examples/ch06-agentic-ai/`](../ch06-agentic-ai/) |
| Row-level filtering behind the **"Viewing as"** selector | `RowLevelSecurity:Enabled` | Chapter 8 | The security predicate from [`examples/ch08/`](../ch08/) |

Row-level security is the one that looks like nothing is gated: the selector is
live in Chapter 4, it just doesn't filter. Chapter 8's payoff *is* the same
selector suddenly filtering.

Chapter 4 features are **not** flags. The base chart — including the `REGEXP_*`
card — is simply part of the app.

The Research page reads the **`wardgeneral-research` named replica**, which
already exists: [Chapter 3](../ch03-architecture/README.md) provisions it and
`06-replicas.sql` surfaces it. Only the Chapter 5 proc is missing.

## Files in this folder

| File | What it does |
|---|---|
| `WardGeneral.slnx` | The solution. Three projects, all under `src/`. |
| `build.ps1` | Restore + build. `-Clean` for a from-scratch build, `-Configuration Release` to switch config. Runs `preflight-build.ps1` first. |
| `run.ps1` | Start the app and open your real browser. `-Server` / `-Database` override configuration for this run. |
| `restart.ps1` | Stop, then start. **This is how you flip a feature flag** — `-Enable` takes the complete list of flags to force on. |
| `shutdown.ps1` | Stop the app and free the ports. |
| `preflight-build.ps1` | Checks the .NET 10 SDK is present before building. |
| `preflight-run.ps1` | Checks `az login`, the server firewall, and that the database answers, before starting. `-SkipFirewall` to skip the firewall step. |

### The projects

| Project | What it is |
|---|---|
| `src/WardGeneral.Web` | The Blazor Web App (Interactive Server). Pages, layout, feature flags. |
| `src/WardGeneral.Data` | Class library. Raw ADO.NET over `Microsoft.Data.SqlClient`, one method per stored procedure. No ORM. |
| `src/WardGeneral.Agent` | The Chapter 6 assistant. Project-referenced by `Web` so it **compiles here in Chapter 4**; its UI stays locked until the `AiAgent` flag is on. |

## Configuring the connection

No password appears anywhere. The connection uses
`Authentication=ActiveDirectoryDefault`, which resolves your `az login` identity
through `DefaultAzureCredential`.

`appsettings.json` ships the **shape, not the values** — `Server` is
deliberately empty. Supply yours in one of three places; **highest wins**:

1. `WardGeneral__Server` / `WardGeneral__Database` environment variables — what
   `run.ps1 -Server` sets
2. `appsettings.Development.json` — git-ignored, local to you
3. `appsettings.json` itself

If `Server` is still blank the app **fails at startup** and names all three
places. That is deliberate: a silent fallback to `localhost` is a worse first
five minutes than an explicit error.

## Running it

```powershell
./build.ps1
./run.ps1 -Server <your-server>.database.windows.net
```

Use the server you created in Chapter 2. The app listens on
`https://localhost:7170` (and `http://localhost:5170`) and opens your default
browser.

> Do **not** use the VS Code Simple Browser — it rejects the dev certificate and
> drops the Blazor circuit. `run.ps1` launches your real browser.

To stop:

```powershell
./shutdown.ps1
```

## Flipping a feature flag (later chapters)

```powershell
./restart.ps1 -Enable AiAssistance              # Ch 5 · AI card + Research
./restart.ps1 -Enable AiAgent                   # Ch 6 · chat icon (needs DAB)
./restart.ps1 -Enable RowLevelSecurity          # Ch 8 · the selector starts filtering
./restart.ps1 -Enable AiAssistance,AiAgent      # more than one
./restart.ps1                                   # back to the shipped defaults
```

Three things worth knowing:

- **`-Enable` is the complete list**, not an addition. Any flag you don't name
  is cleared back to what `appsettings.json` says, so a plain `./restart.ps1`
  always returns the app to its defaults. It has to work that way — the switch
  writes process environment variables, which would otherwise outlive the run.
- **A restart is required, a refresh is not enough.** Flags bind as
  `IOptions<FeatureFlags>`, resolved once at startup.
- **Use `restart.ps1`, not `run.ps1`.** `run.ps1` finds the old process still
  listening and simply reopens the browser at it, so the flag looks broken when
  it isn't.

No rebuild is involved. `run.ps1` uses `dotnet run`, so the app reads
`src/WardGeneral.Web/appsettings.json` from the project directory directly.
