# Azure SQL Hyperscale — Book Examples

Companion code for the forthcoming Apress book on **Azure SQL Hyperscale** by
**Bob Ward**. Every hands-on example in the book lives here, organized by chapter.

> **Short link:** this repo is referenced throughout the book as
> **`aka.ms/sqlhyperscalebook`**. Follow that link to reach the repo, then clone
> the URL shown by GitHub's **Code** button (or `gh repo clone`).

> **Status: pre-release.** Chapters are published here as the book is written.
> Folders appear as their chapters are finished.

## The scenario

The book runs one continuous scenario. **Collier Health** is a (fictional) health
system — the Azure SQL *logical server*, `collierhealth`. **Ward General Hospital**
is its flagship hospital — the Hyperscale *database*, `wardgeneral`. The story
grows from one hospital to a national health system, which is what motivates each
Hyperscale capability as the book advances.

**All data is synthetic. There is no real patient data (PHI) anywhere in this
repository — ever.** The dataset was **generated with AI assistance** and, while
plausible, **may not be a fully accurate representation of real medical, clinical,
laboratory, or billing data**. It is provided for **educational and illustrative
purposes only** and must **not** be used for clinical, diagnostic, or any
real-world healthcare decision-making.

## Layout

```
.github/skills/     Copilot skills — open this repo in VS Code and Copilot can
                    run them for you (e.g. "deploy my Hyperscale database")
examples/ch02/      Getting started: provision, connect, build the schema, seed
examples/ch03/      ... (added as chapters are completed)
```

Each chapter's scripts live under `examples/`; the Copilot **skills** that
orchestrate them live under `.github/skills/` so VS Code discovers them the
moment you open the repo.

## Prerequisites

Install these before running the guided deploy:

**Editor + AI (to use the skill)**
- **VS Code** (current build).
- **GitHub Copilot** + **GitHub Copilot Chat** extensions, with **agent mode**, and a Copilot subscription. Skills are an agent-mode feature and are auto-discovered from this repo's `.github/skills/` the moment you open the folder.

**Shells / CLIs (what the scripts call)**
- **PowerShell 7+ (`pwsh`)** — required. The scripts use PowerShell 7 features, so Windows PowerShell 5.1 won't work. Set `pwsh` as your default integrated terminal.
- **Azure CLI 2.60+** (`az`) — signed in with `az login`.

**Database client (for connect-and-verify)**
- **MSSQL extension for VS Code** (`ms-mssql.mssql`) — the book's primary client; used to connect (Microsoft Entra auth) and run `connect-and-verify.sql`.

**Azure account**
- An **Azure subscription** with rights to create a logical server + database (Contributor or a SQL-specific role). See Chapter 2 for subscription options, including the free path. A Hyperscale database **bills from creation** — mind the meter, and see Chapter 2's teardown note.
- A **Microsoft Entra** account — you become the server's Entra admin (no SQL password needed to connect).

**Optional**
- **Azure MCP Server** (`ms-azuretools.vscode-azure-mcp-server`, preview) — lets Copilot drive `az` as structured tools. Not required: the skill runs `az` through the built-in terminal tool.

> **What "tools" does the skill use?** Mostly the **built-in terminal tool** that ships with Copilot agent mode — it runs `az` and the PowerShell script. Azure MCP is an optional add-on; the MSSQL extension is a client *you* drive, not an agent tool.

## Using the examples

Two ways, depending on how hands-on you want to be:

**Guided (recommended).** Clone via **`aka.ms/sqlhyperscalebook`**, open the
folder in **VS Code** with GitHub Copilot, and ask Copilot to *"deploy my
Hyperscale database."* It discovers the `deploy-hyperscale` skill in
`.github/skills/`, walks you through the key create-time decisions (region,
server name, redundancy, auth, size), and runs the deployment.

**By hand.** Open the chapter folder under `examples/` and run the PowerShell
scripts yourself in **PowerShell 7** — `./provision-hyperscale.ps1` (set any
overrides as `$env:*` first), then run `01-schemas.sql` … `05-seed.sql` via the
MSSQL extension or `sqlcmd`.

Either way, **scripts never hard-code secrets** — they read them from
environment variables or prompt you.

### Running the SQL scripts (and re-running them)

Run the five schema scripts **in order once**, then verify:

| Step | Script | What it does |
|---|---|---|
| 1 | `01-schemas.sql` | Creates the `clinical` and `ops` schemas. |
| 2 | `02-tables.sql` | Creates all 13 tables (keys, FKs, constraints, `json` columns). |
| 3 | `03-views.sql` | Creates the `vPatientChart` chart views. |
| 4 | `04-procedures.sql` | Creates the read/write procedures (admit, discharge, record vitals…). |
| 5 | `05-seed.sql` | Seeds ~10 GB of fully synthetic data. Runs ~5–15 min (log-rate gated). |
| ✓ | `verify-data.sql` | Read-only PASS/FAIL check. You want it to end with **`ALL CHECKS PASSED`**. |

**You never drop the database to start over.** Each script is safe to re-run,
but they differ in what they discard:

- `01` is a guarded no-op on re-run.
- **`02` drops and recreates the tables — this discards all data.** Re-run it
  only when you've changed the schema.
- `03` and `04` use `CREATE OR ALTER` — they redefine in place and touch no data.
- **`05` truncates and reseeds — it reloads the data without changing the
  schema.** This is the quick "give me fresh data" path.

So: to reload just the data, re-run **`05` alone**; to rebuild after a schema
change, re-run **`02`→`05`**. Dropping the *database* is never necessary and
would needlessly discard your compute shape, HA replica, and firewall rules.

### Why each script starts with `SET` options

Every `.sql` file opens with the same seven-line block:

```sql
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
```

Those seven are the **exact settings SQL Server requires** to create a filtered
index, indexed view, computed-column index, or JSON index — if any one is wrong,
the `CREATE` fails with **Msg 1934**. `02-tables.sql` needs them for its filtered
unique index on `Encounter`, and `QUOTED_IDENTIFIER` / `ANSI_NULLS` are recorded
on the object at creation, so they also apply to later work (like the JSON index
added in a later chapter).

The preamble is in **every** file for portability: **SSMS** already defaults most
of these ON, but **`sqlcmd` defaults `QUOTED_IDENTIFIER` and `ARITHABORT` OFF**.
With the preamble, the scripts behave identically whether you run them from the
MSSQL extension, SSMS, or `sqlcmd` — so leave it in place and run each file whole.

## License

License TBD (to be set with the publisher before public release).
