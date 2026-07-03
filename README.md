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

- An **Azure subscription** (see the book's Chapter 2 for the options, including
  the free path). A Hyperscale database bills from creation — mind the meter.
- **Azure CLI** (`az login`).
- **VS Code** with the **MSSQL extension** (primary client used in the book).
  Optional: the **Azure MCP Server** for agent-driven `az` operations.

## Using the examples

Two ways, depending on how hands-on you want to be:

**Guided (recommended).** Clone via **`aka.ms/sqlhyperscalebook`**, open the
folder in **VS Code** with GitHub Copilot, and ask Copilot to *"deploy my
Hyperscale database."* It discovers the `deploy-hyperscale` skill in
`.github/skills/`, walks you through the key create-time decisions (region,
server name, redundancy, auth, size), and runs the deployment.

**By hand.** Open the chapter folder under `examples/` and run the scripts
yourself (`provision-hyperscale.azcli`, then `01-schemas.sql` … `05-seed.sql`).

Either way, **scripts never hard-code secrets** — they read them from
environment variables or prompt you.

## License

License TBD (to be set with the publisher before public release).
