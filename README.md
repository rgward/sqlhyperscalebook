<div align="center">

# Azure SQL Hyperscale Unveiled

**The Cloud SQL AI Database for Everyone**

Companion examples for the Apress book by **Bob Ward**

[Book: aka.ms/sqlhyperscaleunveiled](https://aka.ms/sqlhyperscaleunveiled) •
[Code: aka.ms/sqlhyperscalebook](https://aka.ms/sqlhyperscalebook) •
[GitHub repository](https://github.com/rgward/sqlhyperscalebook)

[High-resolution book cover (PNG)](figures/book-cover.png) •
[Book GIF](figures/book-chapters.gif) •
[4K book video](figures/book-chapters-4k.mp4)

Special thanks to **Kendal Van Dyke** for reviewing both the book and this repository.

[![Repository checks](https://github.com/rgward/sqlhyperscalebook/actions/workflows/repository-checks.yml/badge.svg)](https://github.com/rgward/sqlhyperscalebook/actions/workflows/repository-checks.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Azure SQL Hyperscale](https://img.shields.io/badge/Azure%20SQL-Hyperscale-0078D4.svg)](https://aka.ms/sqlhyperscale)
[![PowerShell 7+](https://img.shields.io/badge/PowerShell-7%2B-5391FE.svg)](https://aka.ms/powershell)
[![.NET 10](https://img.shields.io/badge/.NET-10-512BD4.svg)](https://dotnet.microsoft.com/download)

[Quick start](#quick-start) •
[Chapter guide](#chapter-guide) •
[Prerequisites](#prerequisites) •
[Costs and cleanup](#costs-and-cleanup) •
[Figures](figures/README.md)

</div>

---

## About this repository

This repository contains every hands-on example from *Azure SQL Hyperscale
Unveiled*. Across nine chapters, the examples build one Azure SQL Hyperscale
database and one application, then take them from provisioning and
architecture through AI and agents to observability, security, resiliency, and
performance. Each chapter folder has its own README with prerequisites, run
order, re-run rules, and cleanup.

GitHub Copilot **skills** in [`.github/skills/`](.github/skills/) can run each
chapter's workflow for you. Open the repository in VS Code and use the prompts
printed in the book.

- **Book:** *Azure SQL Hyperscale Unveiled: The Cloud SQL AI Database for Everyone*
- **Author:** Bob Ward, with a foreword by Priya Sathy
- **Publisher:** [Apress](https://link.springer.com/book/10.1007/979-8-8688-3467-7)
- **ISBN:** 979-8-8688-3466-0 (print) · 979-8-8688-3467-7 (eBook)
- **Book short link:** [aka.ms/sqlhyperscaleunveiled](https://aka.ms/sqlhyperscaleunveiled)
- **Code short link:** [aka.ms/sqlhyperscalebook](https://aka.ms/sqlhyperscalebook)

The code short link points to the author's repository,
[rgward/sqlhyperscalebook](https://github.com/rgward/sqlhyperscalebook), where
updates land first. The book's front matter also lists the Apress source-code
repository, [Apress/Inside-Azure-SQL-Hyperscale](https://github.com/Apress/Inside-Azure-SQL-Hyperscale),
which carries the same examples.

## Contents

- [Quick start](#quick-start)
- [The scenario](#the-scenario)
- [Chapter guide](#chapter-guide)
- [Repository layout](#repository-layout)
- [Prerequisites](#prerequisites)
- [Using the examples](#using-the-examples)
- [Costs and cleanup](#costs-and-cleanup)
- [Conventions](#conventions)
- [Testing the examples](#testing-the-examples)
- [Figures](#figures)
- [Links from the book](#links-from-the-book)
- [Support and contributing](#support-and-contributing)
- [License](#license)

## Quick start

1. **Install the prerequisites** for Chapter 2. See [Prerequisites](#prerequisites).
2. **Get the code** and open the repository root in VS Code:

   ```powershell
   git clone https://github.com/rgward/sqlhyperscalebook.git
   code sqlhyperscalebook
   ```

   You can also use **Code → Download ZIP** on GitHub. Open the repository
   root, not a chapter folder, so VS Code discovers the Copilot skills.
3. **Deploy the database.** In Copilot Chat, switch to agent mode and ask:
   *"Deploy my Hyperscale database."* The `deploy-hyperscale` skill walks you
   through each create-time decision and asks for approval before it creates
   anything.
4. **Continue chapter by chapter** with the [chapter guide](#chapter-guide).

> [!WARNING]
> A Hyperscale database bills from the moment it's created, and there is no
> free Hyperscale tier. Review [Costs and cleanup](#costs-and-cleanup) before
> you deploy.

## The scenario

The book follows one continuous story. A fictional health system grows from
one hospital to a national network, and each stage motivates the next
Hyperscale capability.

| In the story | In Azure |
| --- | --- |
| **Collier Health**, a fictional health system | The Azure SQL logical server, `collierhealth` |
| **Ward General Hospital**, its flagship hospital | The Hyperscale database, `wardgeneral` |
| Ward General's patient research | The optional named replica, `wardgeneral-research` |

> [!IMPORTANT]
> **All data is synthetic. There is no real patient data (PHI) anywhere in this
> repository.** The dataset was generated with AI assistance and, while
> plausible, may not accurately represent real medical, clinical, laboratory,
> or billing data. It is provided for educational and illustrative purposes
> only and must not be used for clinical, diagnostic, or any real-world
> healthcare decision-making.

## Chapter guide

| Ch. | Book chapter | What you'll do | Examples |
| :---: | --- | --- | --- |
| 1 | Is It Hyper or Scale? Why Not Both? | The story behind Hyperscale | [Figures](figures/README.md#chapter-1) · [Links](#links-from-the-book) |
| 2 | Getting Started with a Hyperscale Database for Workloads of Any Size | Provision Hyperscale, connect, create the schema, and load ~12 GB of synthetic data | [`ch02-getting-started`](examples/ch02-getting-started/README.md) |
| 3 | Exploring the Architecture of Hyperscale | Make each Hyperscale tier visible with read-only DMV queries | [`ch03-architecture`](examples/ch03-architecture/README.md) |
| 4 | Building Your First Hyperscale Application | Build and run the Ward General patient chart, a Blazor app | [`ch04-first-app`](examples/ch04-first-app/README.md) |
| 5 | Making the Application AI-Ready | Embeddings, a DiskANN vector index, in-engine AI assistance, and an AI gateway | [`ch05-ai-ready-sql`](examples/ch05-ai-ready-sql/README.md) |
| 6 | Agentic AI and Hyperscale Applications | A shift-handoff agent over seven SQL MCP tools, with an approval-gated write | [`ch06-agentic-ai`](examples/ch06-agentic-ai/README.md) |
| 7 | Observability for Hyperscale | Investigate performance, availability, and engine events | [`ch07-observability`](examples/ch07-observability/README.md) |
| 8 | Securing Data in the Cloud with Hyperscale | Row-Level Security in the app, auditing, and optional TDE with a customer-managed key | [`ch08-security`](examples/ch08-security/README.md) |
| 9 | High Availability and Resiliency in Hyperscale | Retry through a failover, restore to a point in time, and add a cross-region geo-replica | [`ch09-ha-resiliency`](examples/ch09-ha-resiliency/README.md) |
| 10 | Turbocharging and Optimizing Performance in Hyperscale | Scale compute under load, grow the data, and tune with JSON indexes and memory grant feedback | [`ch10-performance`](examples/ch10-performance/README.md) |
| 11 | Azure Is the Best Cloud for SQL | Migration and the wider Azure data platform | [Figures](figures/README.md#chapter-11) · [Links](#links-from-the-book) |

The [database object catalog](examples/ch06-agentic-ai/OBJECT-CATALOG.md) maps
every reader-deployed object through Chapter 7 to its owning chapter, purpose,
and caller.

## Repository layout

```text
.
├── .github/
│   ├── skills/                 GitHub Copilot skills, one per guided workflow
│   └── workflows/              Repository checks
├── examples/
│   ├── ch02-getting-started/   Provision, connect, create the schema, seed the data
│   ├── ch03-architecture/      Read-only DMV scripts for each Hyperscale tier
│   ├── ch04-first-app/         The Ward General app, shared by Chapters 4–10
│   ├── ch05-ai-ready-sql/      Embeddings, vector search, AI assistance, AI gateway
│   ├── ch06-agentic-ai/        The shift-handoff agent, DAB, and the SQL MCP server
│   ├── ch07-observability/     Performance, availability, and engine events
│   ├── ch08-security/          Row-Level Security, auditing, and TDE
│   ├── ch09-ha-resiliency/     Failover, point-in-time restore, and geo-replication
│   └── ch10-performance/       Compute scaling, data growth, and tuning
├── figures/                    Every book figure by chapter, plus SVG sources
├── tests/                      Automated test suite for every example
├── tools/                      Repository validation
├── CONTRIBUTING.md
├── SECURITY.md
└── LICENSE
```

## Prerequisites

You don't need every tool on day one. Install the **required** set before the
Chapter 2 deploy and add the rest when a chapter asks for it. Each chapter's
README lists its exact prerequisites.

### Required to start (Chapter 2)

| Requirement | Notes |
| --- | --- |
| **VS Code** | Current build. |
| **GitHub Copilot** and **GitHub Copilot Chat** | Agent mode and a Copilot subscription. Skills are an agent-mode feature, discovered automatically from `.github/skills/` when you open the repository. |
| **PowerShell 7+** (`pwsh`) | Not installed with Windows, which ships Windows PowerShell 5.1. Install it separately and set `pwsh` as your default integrated terminal. |
| **Azure CLI 2.60+** (`az`) | Signed in with `az login`. |
| **MSSQL extension for VS Code** (`ms-mssql.mssql`) | The book's primary database client. It runs inside VS Code. |
| **Azure subscription** | Rights to create a logical server and database (Contributor or a SQL-specific role). To follow the early chapters for free, see [Using the free Azure SQL Database offer](examples/ch02-getting-started/README.md#using-the-free-azure-sql-database-offer-instead). |
| **Microsoft Entra account** | You become the server's Entra admin, so no SQL password is needed to connect. |

### Needed in later chapters

| Tool | First needed | Used for |
| --- | :---: | --- |
| **go-sqlcmd** (the Go-based `sqlcmd`, not the legacy ODBC one) | 4 | Preflight checks and script-driven SQL in Chapters 4–10 |
| **.NET 10 SDK** and a trusted **HTTPS dev certificate** (`dotnet dev-certs https --trust`) | 4 | Building and running the Ward General app |
| **Data API builder (DAB) CLI 2.0+** | 6 | The SQL MCP server the agent calls |
| **ODBC Driver 18 for SQL Server** and **sqlsim** ([aka.ms/sqlsimtools](https://aka.ms/sqlsimtools)) | 10 | The workload demos |

### Optional

- **Git.** The easiest way to get the examples and pick up updates; VS Code's
  source control features need it. **Code → Download ZIP** works too.
- **SQL Server Management Studio (SSMS).** An alternative client the book also
  shows. It runs on Windows only; on macOS or Linux, use VS Code with the MSSQL
  extension.
- **Azure MCP Server** (`ms-azuretools.vscode-azure-mcp-server`, preview). Lets
  Copilot drive `az` as structured tools. Not required: the skills run `az`
  through Copilot's built-in terminal tool.

### Supported operating systems

| Tool | Windows | macOS | Linux |
| --- | :---: | :---: | :---: |
| VS Code, GitHub Copilot, MSSQL extension | ✓ | ✓ | ✓ |
| PowerShell 7, Azure CLI | ✓ | ✓ | ✓ |
| go-sqlcmd | ✓ | ✓ | ✓ |
| .NET 10 SDK, DAB CLI | ✓ | ✓ | ✓ |
| ODBC Driver 18 for SQL Server | ✓ | ✓ | ✓ |
| SSMS (optional) | ✓ | — | — |
| sqlsim and the Chapter 10 workload demos | ✓ | — | — |

The scripts are written for Windows, macOS, and Linux, and are validated on
Windows. The Chapter 10 sqlsim workload demos run on Windows only.

## Using the examples

### Guided, with GitHub Copilot (recommended)

Open the repository root in VS Code, switch Copilot Chat to agent mode, and use
the prompts printed in the book, for example *"Deploy my Hyperscale
database."* Copilot loads the matching skill from `.github/skills/`, explains
each decision, and asks for approval before it creates or changes Azure
resources. Each chapter README lists its book prompts.

<details>
<summary><b>Copilot skills by chapter</b></summary>

| Chapter | Skill | What it does |
| :---: | --- | --- |
| 2 | `deploy-hyperscale` | Interview-driven deploy of the logical server and `wardgeneral` |
| 2 | `verify-deployment` | Summarize the deployment from the Azure Activity Log |
| 4 | `wardgeneral-app` | Build, configure, and run the Ward General app |
| 5 | `ai-ready-app` | Deploy the AI resources and the AI-ready SQL objects |
| 6 | `wardgeneral-agent` | Add the shift-handoff agent, DAB, and the SQL MCP server |
| 7 | `observe-hyperscale-performance` | Run the performance investigation |
| 7 | `observe-hyperscale-availability` | Run the availability investigation |
| 7 | `observe-hyperscale-engine-events` | Inspect engine events, errors, and connections |
| 8 | `secure-hyperscale` | Enable Row-Level Security in the app; optional TDE with a customer-managed key |
| 8 | `audit-wardgeneral` | Audit app activity and find it in Log Analytics |
| 9 | `test-hyperscale-failover` | Observe application retry during a manual failover |
| 9 | `recover-wardgeneral-pitr` | Create and verify a point-in-time restore test copy |
| 9 | `deploy-wardgeneral-geo-replica` | Create and verify a cross-region geo-replica |
| 10 | `scale-wardgeneral-compute` | Run the workload at 8, 16, and 40 vCores |
| 10 | `grow-wardgeneral-database` | Drive write growth and find the constraint |
| 10 | `tune-wardgeneral-data` | JSON indexing, memory grant feedback, and index evaluation |
| 10 | `scale-and-tune-wardgeneral` | Run all three Chapter 10 demos in order |

</details>

### By hand

Every skill runs scripts you can run yourself. Open the chapter folder under
`examples/` and follow its README in **PowerShell 7**. For Chapter 2, that's
`./provision-hyperscale.ps1` (set any overrides as `$env:*` first),
optionally `./add-replicas.ps1` for the `wardgeneral-research` named replica,
then `01-schemas.sql` through `05-seed.sql` in the MSSQL extension or `sqlcmd`.
Scripts never hard-code secrets; they read them from environment variables or
prompt you.

### Working with Copilot

- **Copilot may edit scripts in your clone.** If you ask it to adapt
  something, such as a different region or compute model, it can change a
  script or SQL file to do it. That's expected, and it's your copy. Use
  `git status` and `git diff` to see what changed, and `git restore <file>` to
  put a file back. Please don't open pull requests from local adaptations; if
  you find a real problem in an example,
  [open an issue](https://github.com/rgward/sqlhyperscalebook/issues).
- **Approving actions.** Before Copilot runs a command or tool, VS Code asks
  for approval. You can approve a single use, or grant approval for the
  session, the workspace, or all future uses. Approving each step is the
  strict choice; allowing more saves clicks when you trust what it's doing.
  Avoid **Allow all** and **Autopilot** for these examples: the skills ask for
  your approval in chat before creating billable Azure resources, and Autopilot
  can answer those questions on its own. See
  [Manage approvals and permissions](https://code.visualstudio.com/docs/agents/run/approvals).
- **Chat or terminal?** Answer the skills' questions in chat; to accept a
  default, reply **ok**. Only a few steps need the terminal: signing in with
  `az login`, and typing the masked SQL admin password during the Chapter 2
  deploy. Your password never goes into chat.
- **Where output appears.** Short commands show their output in chat.
  Long-running processes, such as the Ward General app, run in a terminal
  Copilot opens; look for it in the **Terminal** panel.

## Costs and cleanup

> [!WARNING]
> There is no free Hyperscale tier. The database bills from creation, and
> replicas, AI services, and other resources add charges. Stopping the local
> application does not stop Azure billing.

The repository doesn't print prices, because they vary by region and change
over time. For live numbers, run Chapter 2's
[`estimate-cost.ps1`](examples/ch02-getting-started/estimate-cost.ps1), which
reads the public Azure Retail Prices API, or use the
[Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/).
This table lists everything the examples can create that bills, and how to
stop it:

| Chapter | What bills | When it bills | How to stop it |
| :---: | --- | --- | --- |
| 2 | `wardgeneral`: Hyperscale `HS_Gen5_8` primary **and** its HA replica, plus storage and backup storage | **Always**, from creation | Delete it; see [Chapter 2 cost and cleanup](examples/ch02-getting-started/README.md#cost-and-cleanup) |
| 2 (optional) | `wardgeneral-research` named replica, serverless | Always, at least its minimum vCores | Delete the named replica |
| 5 | Microsoft Foundry model deployments (`gpt-5`, embeddings) | Per token used | [`reset-ai-azure.ps1`](examples/ch05-ai-ready-sql/reset-ai-azure.ps1) |
| 5 | API Management StandardV2 gateway | **Always** while it exists; `-NoGateway` skips it | `reset-ai-azure.ps1` |
| 5 | Content Safety (with the gateway) | Free F0 tier by default (one per subscription); per transaction with `CS_SKU=S0` | `reset-ai-azure.ps1` |
| 7 (optional) | Log Analytics workspace for AzureSQLErrors | Per GB ingested and retained | `teardown-azuresqlerrors.ps1` |
| 8 (optional) | Log Analytics workspace for auditing | Per GB ingested and retained | `teardown-auditing.ps1` |
| 8 (optional) | Key Vault for TDE with a customer-managed key | Per key operation; purge protection keeps it for its retention period | No automated teardown; see the [TDE README](examples/ch08-security/tde/README.md) |
| 9 | Point-in-time restore test copy, serverless | Storage always; compute unless paused | `cleanup-pitr.ps1` |
| 9 (optional) | Geo-replica logical server and database, same size as the primary | **Always** | `cleanup-geo-replica.ps1` |
| 10 | `wardgeneral` scaled to 16, then 40 vCores (the HA replica too), and about 12 GB more storage per growth interval | **Always**, at the larger size until you scale back | `scale-compute.ps1 -TargetServiceObjective HS_Gen5_8`; see [Chapter 10 cost and cleanup](examples/ch10-performance/README.md#cost-and-cleanup--scale-back-when-you-finish) |

The Ward General app, DAB, and the agent run on your machine and add no Azure
charges of their own beyond the model calls above.

**Free trial or Visual Studio subscription?** Monthly credits differ by
subscription, so check yours against the estimate. The **Always** rows use
credit fastest, so delete or scale back between sessions. These subscriptions
have a [spending limit](https://learn.microsoft.com/azure/cost-management-billing/manage/spending-limit)
on by default: when the credit runs out, Azure disables the deployed services
for the rest of the billing period. The
[free Azure SQL Database offer](examples/ch02-getting-started/README.md#using-the-free-azure-sql-database-offer-instead)
covers the SQL and application work in the early chapters.

### Safety and local configuration

- **Dev/test only.** These are educational examples, not a production
  deployment template. Never point a load generator at a production database.
- **Your names stay local.** Keep resource names in each chapter's local
  environment file, copied from its template. Environment files, development
  settings, build output, and generated Chapter 10 evidence are git-ignored.
  Never commit passwords, access tokens, connection strings, or your own
  deployment details.
- **Preview features.** Some examples use preview features. Check the chapter's
  notes and current Microsoft documentation before running them; availability
  and behavior can change independently of the book.

## Conventions

### Running and re-running the Chapter 2 schema scripts

Run the five schema scripts **in order once**, then verify:

| Step | Script | What it does |
| :---: | --- | --- |
| 1 | `01-schemas.sql` | Creates the `clinical` and `ops` schemas. |
| 2 | `02-tables.sql` | Creates all 16 tables (keys, foreign keys, constraints, `json` columns). |
| 3 | `03-views.sql` | Creates the `vPatientChart` chart views. |
| 4 | `04-procedures.sql` | Creates the read and write procedures (admit, discharge, record vitals, and more). |
| 5 | `05-seed.sql` | Seeds roughly **12 GB** of fully synthetic data. Runs ~5–15 minutes (log-rate gated). |
| ✓ | `verify-data.sql` | Read-only PASS/FAIL check. It should end with **`ALL CHECKS PASSED`**. |

**You never drop the database to start over.** Each script is safe to re-run,
but they differ in what they discard:

- `01` is a guarded no-op on re-run.
- **`02` drops and recreates the tables, discarding all data.** Re-run it only
  after a schema change.
- `03` and `04` use `CREATE OR ALTER`; they redefine in place and touch no data.
- **`05` truncates and reseeds.** It reloads the data without changing the
  schema.

To reload only the data, re-run **`05`**. To rebuild after a schema change,
re-run **`02` through `05`**. Dropping the database is never necessary and
would discard your compute shape, HA replica, and firewall rules.

### Why schema scripts start with `SET` options

Every `.sql` file that creates or alters schema objects (tables, views,
procedures, functions, indexes) opens with the same seven lines:

```sql
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
```

These are the settings SQL Server requires to create a filtered index, indexed
view, computed-column index, or JSON index; if any one is wrong, the `CREATE`
fails with **Msg 1934**. `QUOTED_IDENTIFIER` and `ANSI_NULLS` are also recorded
on each object when it's created, so they affect later work such as the JSON
index in a later chapter.

SSMS defaults most of these on, but **`sqlcmd` defaults `QUOTED_IDENTIFIER` and
`ARITHABORT` off**. With the preamble, each script behaves the same in the
MSSQL extension, SSMS, or `sqlcmd`, so leave it in place and run each file
whole. Read-only diagnostic queries, cleanup scripts, and sqlsim workload
statements create nothing, so they don't carry it.

## Testing the examples

An automated suite in [`tests/`](tests/README.md) covers every example in the
repository, in two tiers:

| Tier | What it does | Azure |
| --- | --- | :---: |
| **Offline** | Checks every script, Copilot skill, book prompt, and book link. A recording fake `az` confirms that every billable or destructive script previews by default, that its approval switch makes only the intended change, and that its safety guards refuse. It also checks that every example is covered by the live tier. Runs on every push. | No |
| **Live** | Builds a separate copy of the book's environment, with the book's names, from a tester-provided `tests/test.env`. Runs every chapter's examples in order against it and checks each documented result, then deletes it. | **Billable** |

```powershell
./tests/Invoke-BookTests.ps1                        # offline, about 2–3 minutes
./tests/Invoke-BookTests.ps1 -Live                  # live: show the plan only
./tests/Invoke-BookTests.ps1 -Live -AcceptCharges   # live: run, then tear down
```

The offline tier needs PowerShell 7, Pester 5.5 or later, and the .NET 10 SDK.
The live tier creates the same billable resources a reader does and takes
several hours; see the [test suite README](tests/README.md) for setup, options,
and cost.

A separate evaluation, `./tests/Measure-SkillRouting.ps1`, runs each prompt
printed in the book through GitHub Copilot CLI. It records whether Copilot
picks the intended skill, and whether it loads every skill at all. It's safe,
because Copilot can only choose a skill, not run anything, but its results can
vary by model, so it isn't part of CI.

## Figures

Every captioned figure in the book is published, by chapter, in
[`figures/`](figures/README.md), along with editable SVG sources for the
architecture diagrams. Many printed figures are hard to read at book size;
open them here to zoom in.

<p align="center">
  <a href="figures/README.md#chapter-3">
    <img src="figures/ch03-architecture/ch03-figure-01-architecture.svg" alt="Azure SQL Hyperscale architecture (Figure 3-2)" width="900">
  </a>
  <br>
  <sub>Figure 3-2. The modern Azure SQL Hyperscale architecture</sub>
</p>

## Links from the book

Each chapter README under `examples/` ends with a **Links from the book**
list: every web link printed in that chapter, in order, so you can click
instead of typing. Chapters 1 and 11 have no example folder, so their links are
here.

<details>
<summary><b>Chapter 1 links</b></summary>

- Socrates research paper (the architecture behind Hyperscale) — <https://aka.ms/socratespaper>
- Azure SQL Database resource limits — <https://aka.ms/sqldbresourcelimits>
- Azure SQL service level agreement (SLA) — <https://aka.ms/azuresqlsla>

</details>

<details>
<summary><b>Chapter 11 links</b></summary>

- Microsoft Foundry — <https://ai.azure.com>
- Foundry Agent Service — <https://learn.microsoft.com/azure/foundry/agents/overview>
- SqlPackage — <https://aka.ms/sqlpackages>
- Azure Database Migration Service — <https://aka.ms/dms>
- Database compatibility level — <https://aka.ms/dbcompat>
- T-SQL differences between SQL Server and Azure SQL Database — <https://aka.ms/azuresqldbtsqldiff>
- Microsoft Entra authentication with Microsoft.Data.SqlClient — <https://learn.microsoft.com/sql/connect/ado-net/sql/azure-active-directory-authentication>
- Azure SQL trigger for Azure Functions — <https://learn.microsoft.com/azure/azure-functions/functions-bindings-azure-sql-trigger>
- Change event streaming (CES) — <https://learn.microsoft.com/sql/relational-databases/track-changes/change-event-streaming/overview>
- Fabric Mirroring for SQL — <https://aka.ms/sqlmirroring>
- Azure SQL Database Container — <https://microsoft.github.io/azure-sql-database-container>
- Azure SQL Hyperscale documentation — <https://aka.ms/sqlhyperscale>
- Azure SQL Foundations companion repo — <https://aka.ms/azuresqlfoundations>
- Azure SQL Foundations video series — <https://aka.ms/azuresqlfoundationseries>
- Bob Ward's presentations — <https://aka.ms/bobwardms>
- sqlsimtools — <https://aka.ms/sqlsimtools>
- Exam DP-800 — <https://aka.ms/dp800/exam>
- Data Exposed — <https://aka.ms/dataexposed>
- Azure SQL blog — <https://aka.ms/azuresqlblog>
- Azure SQL dev blog — <https://devblogs.microsoft.com/azure-sql>

</details>

## Support and contributing

- **Questions, problems, and errata:**
  [open an issue](https://github.com/rgward/sqlhyperscalebook/issues) with the
  chapter, script, expected behavior, and sanitized error output. Don't include
  credentials, subscription details, or local environment files.
- **Discussion:** share your experience with the book and examples in
  [Discussions](https://github.com/rgward/sqlhyperscalebook/discussions).
- **Contributing:** see [CONTRIBUTING.md](CONTRIBUTING.md) for validation
  commands and guidelines.
- **Security:** see [SECURITY.md](SECURITY.md) to report a vulnerability
  privately.

## License

The examples are licensed under the [MIT License](LICENSE).