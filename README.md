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
repository — ever.**

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

## License

License TBD (to be set with the publisher before public release).
