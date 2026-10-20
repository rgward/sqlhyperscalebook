# Azure SQL Hyperscale Unveiled — Book Examples

Companion code for the Apress book **Azure SQL Hyperscale Unveiled** by
**Bob Ward**. Every hands-on example in the book lives here, organized by chapter.

> **Short link:** this repo is referenced throughout the book as
> **`aka.ms/sqlhyperscalebook`**. Follow that link to reach the repo, then clone
> the URL shown by GitHub's **Code** button (or `gh repo clone`).

**The e-book is now available.** This repository contains the companion examples
for Chapters 2 through 10 and architecture figures. Follow each chapter's README
for its prerequisites, exact run order, re-run rules, and cleanup instructions.

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

```text
.github/skills/            Copilot skills — open this repo in VS Code and Copilot can
                           run them for you (e.g. "deploy my Hyperscale database")
examples/ch02-getting-started/  Getting started: provision, connect, build the schema, seed
examples/ch03-architecture/     Architecture: read-only DMV scripts that make the
                           Hyperscale tiers visible on the database from Chapter 2
examples/ch04-first-app/        The first app: a Blazor patient chart over the
                           Chapter 2 database, and the one connection it makes
examples/ch05-ai-ready-sql/     AI-ready SQL: embeddings, a vector index, in-engine
                           AI assistance and vector search — plus the APIM AI
                           gateway the engine calls through
examples/ch06-agentic-ai/       Agentic AI: a two-turn shift handoff over seven
                           bounded SQL MCP tools and an approval-gated write
examples/ch07-observability/    Observability: performance, availability, engine
                           events, retained errors, and connection history
examples/ch08-security/         Security: Row-Level Security in Ward General and
                           an optional bounded Azure SQL auditing investigation
examples/ch09-ha-resiliency/    Resiliency: observe application retry during a
                           manual failover, create a verified PITR test copy,
                           and deploy a cross-region Hyperscale geo-secondary
examples/ch10-performance/      Performance: scale compute under load, grow the
                           existing database, then demonstrate JSON indexing
                           and memory grant feedback
figures/                   Every book figure by chapter, plus the SVG diagram sources
```

## Chapter guide

| Chapter | Examples |
| --- | --- |
| 2 | [Getting started](examples/ch02-getting-started/README.md) |
| 3 | [Hyperscale architecture](examples/ch03-architecture/README.md) |
| 4 | [Your first application](examples/ch04-first-app/README.md) |
| 5 | [AI-ready SQL](examples/ch05-ai-ready-sql/README.md) |
| 6 | [Agentic AI](examples/ch06-agentic-ai/README.md) |
| 7 | [Observability](examples/ch07-observability/README.md) |
| 8 | [Security](examples/ch08-security/README.md) |
| 9 | [High availability and resiliency](examples/ch09-ha-resiliency/README.md) |
| 10 | [Scale and tune](examples/ch10-performance/README.md) |

Each chapter's scripts live under `examples/`; the Copilot **skills** that
orchestrate them live under `.github/skills/` so VS Code discovers them the
moment you open the repo.

The [database object catalog](examples/ch06-agentic-ai/OBJECT-CATALOG.md) maps
every reader-deployed object through Chapter 7 to its owning chapter, purpose,
and application, SQL, or MCP caller.

## Prerequisites

Install these before running the guided deploy:

### Editor + AI

- **VS Code** (current build).
- **GitHub Copilot** + **GitHub Copilot Chat** extensions, with **agent mode**, and a Copilot subscription. Skills are an agent-mode feature and are auto-discovered from this repo's `.github/skills/` the moment you open the folder.

### Shells and CLIs

- **PowerShell 7+ (`pwsh`)** — required. The scripts use PowerShell 7 features, so Windows PowerShell 5.1 won't work. Set `pwsh` as your default integrated terminal.
- **Azure CLI 2.60+** (`az`) — signed in with `az login`.

### Database client

- **MSSQL extension for VS Code** (`ms-mssql.mssql`) — the book's primary client; used to connect (Microsoft Entra auth) and run `connect-and-verify.sql`.

### Azure account

- An **Azure subscription** with rights to create a logical server + database (Contributor or a SQL-specific role). A Hyperscale database **bills from creation** — mind the meter. To follow the early chapters for free instead, see [Using the free Azure SQL Database offer](examples/ch02-getting-started/README.md#using-the-free-azure-sql-database-offer-instead).
- A **Microsoft Entra** account — you become the server's Entra admin (no SQL password needed to connect).

### Optional

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
overrides as `$env:*` first), optionally `./add-replicas.ps1` to add the
`wardgeneral-research` named replica (used from Chapter 5), then
run `01-schemas.sql` … `05-seed.sql` via the MSSQL extension or `sqlcmd`.

Either way, **scripts never hard-code secrets** — they read them from
environment variables or prompt you.

### Cost, safety, and local configuration

- **Dev/test only.** These are educational examples, not a production deployment
  template. Never point a load generator at a production database.
- **There is no free Hyperscale tier.** The database bills from creation;
  replicas, AI services, and other resources can add charges. Review the
  chapter's cost notes before creating resources and its cleanup instructions
  when you finish. Stopping the local application does not stop Azure billing.
- Keep your resource names in the chapter's local environment file, copied
  from its template. Environment files, development settings, build output,
  and generated Chapter 10 evidence are git-ignored. Never commit passwords,
  access tokens, connection strings, or your own deployment details.
- Some examples use preview features. Check the chapter's feature notes and
  current Microsoft documentation before running them; availability and
  behavior can change independently of the book.

### Running the SQL scripts (and re-running them)

Run the five schema scripts **in order once**, then verify:

| Step | Script | What it does |
| --- | --- | --- |
| 1 | `01-schemas.sql` | Creates the `clinical` and `ops` schemas. |
| 2 | `02-tables.sql` | Creates all 16 tables (keys, FKs, constraints, `json` columns). |
| 3 | `03-views.sql` | Creates the `vPatientChart` chart views. |
| 4 | `04-procedures.sql` | Creates the read/write procedures (admit, discharge, record vitals…). |
| 5 | `05-seed.sql` | Seeds the database to roughly **12 GB** of fully synthetic data. Runs ~5–15 min (log-rate gated). |
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

### Why the schema scripts start with `SET` options

Every `.sql` file that creates or alters schema objects — tables, views,
procedures, functions, indexes — opens with the same seven-line block:

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

The preamble is in each of those files for portability: **SSMS** already defaults most
of these ON, but **`sqlcmd` defaults `QUOTED_IDENTIFIER` and `ARITHABORT` OFF**.
With the preamble, the scripts behave identically whether you run them from the
MSSQL extension, SSMS, or `sqlcmd` — so leave it in place and run each file whole.
Read-only diagnostic queries, cleanup scripts, and the sqlsim workload
statements create nothing, so they don't carry it.

## Figures

Every captioned figure in the book is published here, under `figures/<chapter>/`,
named by its book number — `ch02-fig-06-…` is Figure 2-6. Some printed figures
are hard to read at book size; open the file here to zoom in.

![The road to Azure SQL Hyperscale](figures/ch01-introduction/ch01-figure-01-timeline.svg)

### Chapter 1

| Figure | Caption |
| --- | --- |
| [1-1](figures/ch01-introduction/ch01-fig-01-the-road-to-azure-sql-hyperscale.png) | The road to Azure SQL Hyperscale |
| [1-2](figures/ch01-introduction/ch01-fig-02-hyperscale-is-built-for-mission-critical-applications.png) | Hyperscale is built for mission-critical applications |

### Chapter 2

| Figure | Caption |
| --- | --- |
| [2-1](figures/ch02-getting-started/ch02-fig-01-azure-sql-in-the-azure-portal.png) | Azure SQL in the Azure portal |
| [2-2](figures/ch02-getting-started/ch02-fig-02-creating-a-hyperscale-database-in-the-azure-portal.png) | Creating a Hyperscale database in the Azure portal |
| [2-3](figures/ch02-getting-started/ch02-fig-03-files-and-scripts-in-vs-code-to-deploy-hyperscale.png) | Files and scripts in VS Code to deploy Hyperscale |
| [2-4](figures/ch02-getting-started/ch02-fig-04-using-ai-assistance-to-make-decisions-like-zone-redundancy.png) | Using AI assistance to make decisions like Zone Redundancy |
| [2-5](figures/ch02-getting-started/ch02-fig-05-confirming-choices-before-deploy.png) | Confirming choices before deploy |
| [2-6](figures/ch02-getting-started/ch02-fig-06-hyperscale-deployment-confirmation.png) | Hyperscale deployment confirmation |
| [2-7](figures/ch02-getting-started/ch02-fig-07-connecting-with-the-mssql-extension.png) | Connecting with the MSSQL extension |
| [2-8](figures/ch02-getting-started/ch02-fig-08-the-azure-activity-log-for-the-hyperscale-deployment.png) | The Azure Activity log for the Hyperscale deployment |
| [2-9](figures/ch02-getting-started/ch02-fig-09-using-ssms-with-azure-sql-hyperscale.png) | Using SSMS with Azure SQL Hyperscale |
| [2-10](figures/ch02-getting-started/ch02-fig-10-using-ghcp-with-your-schema.png) | Using GHCP with your schema |
| [2-11](figures/ch02-getting-started/ch02-fig-11-using-ghcp-with-ssms-to-explore-data.png) | Using GHCP with SSMS to explore data |

### Chapter 3

| Figure | Caption |
| --- | --- |
| [3-1](figures/ch03-architecture/ch03-fig-01-the-socrates-architecture.png) | The Socrates architecture |
| [3-2](figures/ch03-architecture/ch03-fig-02-the-modern-azure-sql-hyperscale-architecture.png) | The modern Azure SQL Hyperscale architecture |
| [3-3](figures/ch03-architecture/ch03-fig-03-looking-at-hyperscale-tiers.png) | Looking at Hyperscale tiers |
| [3-4](figures/ch03-architecture/ch03-fig-04-the-primary-compute-in-hyperscale.png) | The Primary Compute in Hyperscale |
| [3-5](figures/ch03-architecture/ch03-fig-05-limits-for-hyperscale-primary-compute.png) | Limits for Hyperscale Primary Compute |
| [3-6](figures/ch03-architecture/ch03-fig-06-tempdb-files-on-primary-compute.png) | Tempdb files on Primary Compute |
| [3-7](figures/ch03-architecture/ch03-fig-07-the-log-service.png) | The Log Service |
| [3-8](figures/ch03-architecture/ch03-fig-08-page-servers.png) | Page Servers |
| [3-9](figures/ch03-architecture/ch03-fig-09-data-file-storage-in-hyperscale.png) | Data file storage in Hyperscale |
| [3-10](figures/ch03-architecture/ch03-fig-10-hyperscale-replicas.png) | Hyperscale replicas |
| [3-11](figures/ch03-architecture/ch03-fig-11-list-of-hyperscale-replicas.png) | List of Hyperscale replicas |
| [3-12](figures/ch03-architecture/ch03-fig-12-end-to-end-flows-in-hyperscale.png) | End-to-end flows in Hyperscale |

### Chapter 4

| Figure | Caption |
| --- | --- |
| [4-1](figures/ch04-first-app/ch04-fig-01-the-digital-chart-application.png) | The digital chart application |
| [4-2](figures/ch04-first-app/ch04-fig-02-top-of-patient-digital-chart.png) | Top of patient digital chart |
| [4-3](figures/ch04-first-app/ch04-fig-03-bottom-of-the-patient-chart.png) | Bottom of the patient chart |
| [4-4](figures/ch04-first-app/ch04-fig-04-application-architecture.png) | Application architecture |
| [4-5](figures/ch04-first-app/ch04-fig-05-application-source-code-in-the-github-repo-for-the-book.png) | Application source code in the GitHub repo for the book |
| [4-6](figures/ch04-first-app/ch04-fig-06-building-the-application-with-github-copilot-in-vs-code.png) | Building the application with GitHub Copilot in VS Code |
| [4-7](figures/ch04-first-app/ch04-fig-07-how-to-chat-with-your-schema-with-github-copilot.png) | How to chat with your schema with GitHub Copilot |
| [4-8](figures/ch04-first-app/ch04-fig-08-from-the-note-using-regex.png) | From the note using RegEx |

### Chapter 5

| Figure | Caption |
| --- | --- |
| [5-1](figures/ch05-ai-ready-sql/ch05-fig-01-patient-research-in-the-application-using-vector-search.png) | Patient Research in the application using vector search |
| [5-2](figures/ch05-ai-ready-sql/ch05-fig-02-clinical-assistance-in-the-digital-chart.png) | Clinical Assistance in the digital chart |
| [5-3](figures/ch05-ai-ready-sql/ch05-fig-03-application-architecture-with-ai.png) | Application architecture with AI |
| [5-4](figures/ch05-ai-ready-sql/ch05-fig-04-the-hyperscale-vector-architecture.png) | The Hyperscale vector architecture |
| [5-5](figures/ch05-ai-ready-sql/ch05-fig-05-hyperscale-agentic-rag.png) | Hyperscale Agentic RAG |

### Chapter 6

| Figure | Caption |
| --- | --- |
| [6-1](figures/ch06-agentic-ai/ch06-fig-01-llms-and-tools.svg) | LLMs and tools |
| 6-2 | The Model Context Protocol (MCP) — [PNG](figures/ch06-agentic-ai/ch06-fig-02-the-model-context-protocol-mcp.png) · [SVG](figures/ch06-agentic-ai/ch06-fig-02-the-model-context-protocol-mcp.svg) |
| [6-3](figures/ch06-agentic-ai/ch06-fig-03-data-api-builder-dab.png) | Data API Builder (DAB) |
| [6-4](figures/ch06-agentic-ai/ch06-fig-04-using-the-sql-mcp-server-with-dab.png) | Using the SQL MCP Server with DAB |
| [6-5](figures/ch06-agentic-ai/ch06-fig-05-the-ward-general-digital-chart-application-with-ai-agents.png) | The Ward General digital chart application with AI agents |
| [6-6](figures/ch06-agentic-ai/ch06-fig-06-the-agent-chat-feature.png) | The Agent chat feature |
| [6-7](figures/ch06-agentic-ai/ch06-fig-07-the-agent-side-chat-interface.png) | The Agent side chat interface |
| [6-8](figures/ch06-agentic-ai/ch06-fig-08-shift-handoff-candidates.png) | Shift handoff candidates |
| [6-9](figures/ch06-agentic-ai/ch06-fig-09-shift-handoff-approval.png) | Shift handoff approval |
| [6-10](figures/ch06-agentic-ai/ch06-fig-10-shift-handoff-recommendations.png) | Shift handoff recommendations |
| [6-11](figures/ch06-agentic-ai/ch06-fig-11-the-agent-flow.png) | The Agent flow |

### Chapter 7

| Figure | Caption |
| --- | --- |
| [7-1](figures/ch07-observability/ch07-fig-01-azure-monitor-metrics-in-the-portal-for-hyperscale.png) | Azure Monitor metrics in the portal for Hyperscale |
| [7-2](figures/ch07-observability/ch07-fig-02-cpu-spike-for-hyperscale.png) | CPU spike for Hyperscale |
| [7-3](figures/ch07-observability/ch07-fig-03-an-azure-copilot-prompt-for-availability.png) | An Azure Copilot prompt for availability |
| [7-4](figures/ch07-observability/ch07-fig-04-watching-live-data-with-xevent.png) | Watching live data with XEvent |

### Chapter 8

| Figure | Caption |
| --- | --- |
| [8-1](figures/ch08-security/ch08-fig-01-the-wardgeneral-digital-chart-application-with-extra-security.svg) | The WardGeneral digital chart application with extra security |
| [8-2](figures/ch08-security/ch08-fig-02-choosing-a-provider-in-the-digital-chart-application.png) | Choosing a provider in the digital chart application |
| [8-3](figures/ch08-security/ch08-fig-03-shift-handoff-with-rls-applied.png) | Shift handoff with RLS applied |
| [8-4](figures/ch08-security/ch08-fig-04-a-private-link-for-hyperscale.png) | A private link for Hyperscale |
| [8-5](figures/ch08-security/ch08-fig-05-the-flow-of-always-encrypted.png) | The flow of Always Encrypted |
| [8-6](figures/ch08-security/ch08-fig-06-microsoft-defender-for-cloud.png) | Microsoft Defender for Cloud |

### Chapter 9

| Figure | Caption |
| --- | --- |
| [9-1](figures/ch09-ha-resiliency/ch09-fig-01-the-hyperscale-ha-architecture.svg) | The Hyperscale HA architecture |
| [9-2](figures/ch09-ha-resiliency/ch09-fig-02-the-hyperscale-zone-redundancy-architecture.svg) | The Hyperscale Zone Redundancy architecture |
| [9-3](figures/ch09-ha-resiliency/ch09-fig-03-hyperscale-geo-replication-architecture.svg) | Hyperscale Geo-Replication architecture |
| [9-4](figures/ch09-ha-resiliency/ch09-fig-04-the-hyperscale-failover-group-architecture.svg) | The Hyperscale Failover Group architecture |
| [9-5](figures/ch09-ha-resiliency/ch09-fig-05-a-hyperscale-geo-replica.png) | A Hyperscale Geo-Replica |

### Chapter 10

| Figure | Caption |
| --- | --- |
| [10-1](figures/ch10-performance/ch10-fig-01-scaling-the-compute-of-the-wardgeneral-database.png) | Scaling the compute of the wardgeneral database |
| [10-2](figures/ch10-performance/ch10-fig-02-hands-free-data-growth-and-io-for-hyperscale.png) | Hands-free data growth and IO for Hyperscale |
| [10-3](figures/ch10-performance/ch10-fig-03-the-hyperscale-elastic-pool-architecture.svg) | The Hyperscale Elastic Pool architecture |
| [10-4](figures/ch10-performance/ch10-fig-04-json-index-seek-in-hyperscale.png) | JSON index seek in Hyperscale |
| [10-5](figures/ch10-performance/ch10-fig-05-tempdb-spill-due-to-underestimated-memory-grant.png) | Tempdb spill due to underestimated memory grant |
| [10-6](figures/ch10-performance/ch10-fig-06-automatic-index-compaction-in-hyperscale.png) | Automatic Index Compaction in Hyperscale |

### Chapter 11

| Figure | Caption |
| --- | --- |
| [11-1](figures/ch11-azure-best-cloud/ch11-fig-01-why-azure-is-the-best-cloud-for-hyperscale.svg) | Why Azure is the best cloud for Hyperscale |
| [11-2](figures/ch11-azure-best-cloud/ch11-fig-02-the-azure-ai-plane-microsoft-foundry.png) | The Azure AI Plane, Microsoft Foundry |
| [11-3](figures/ch11-azure-best-cloud/ch11-fig-03-using-skills-to-migrate-to-hyperscale-with-dms.svg) | Using skills to migrate to Hyperscale with DMS |

### Diagram sources (SVG)

The architecture diagrams are also published as **SVG** — the source several of
the printed figures were drawn from. They stay crisp at any zoom, and you can open
one and adapt it.

| Chapter | Figure | What it shows |
| --- | --- | --- |
| 1 | [Timeline](figures/ch01-introduction/ch01-figure-01-timeline.svg) | How Hyperscale got here, from SQL Azure to GA. |
| 3 | [Architecture](figures/ch03-architecture/ch03-figure-01-architecture.svg) | The master figure: all four tiers and the paths between them. |
| 3 | [Primary compute](figures/ch03-architecture/ch03-figure-primary-compute.svg) | The primary replica and its local RBPEX cache. |
| 3 | [Log service](figures/ch03-architecture/ch03-figure-02-log-service.svg) | XLOG — the landing zone, the log broker, and who consumes the log. |
| 3 | [Page servers](figures/ch03-architecture/ch03-figure-page-server.svg) | The 128 GB slices and the `GetPage@LSN` path. |
| 3 | [File and storage](figures/ch03-architecture/ch03-figure-file-storage.svg) | The durable tier, and why you pay on actual allocation. |
| 3 | [Replicas](figures/ch03-architecture/ch03-figure-replicas.svg) | HA replicas, named replicas, and what attaches to what. |
| 3 | [Transaction flow](figures/ch03-architecture/ch03-figure-transaction-flow.svg) | One commit, followed across every tier. |
| 4 | [Application architecture](figures/ch04-first-app/ch04-figure-01-application-architecture-wide.svg) | The Ward General app, and the one connection it makes. |
| 5 | [Application architecture](figures/ch05-ai-ready-sql/ch05-figure-01-application-architecture.svg) | The same app once the engine itself calls out to models. |
| 6 | [Application architecture](figures/ch06-agentic-ai/ch06-figure-01-application-architecture.svg) | The same app once an agent, DAB and the SQL MCP server join it. |
| 8 | [Security architecture](figures/ch08-security/ch08-figure-01-application-architecture.svg) | The same app with provider context, Row-Level Security, and the production Private Link path. |

Chapters 4, 5, 6 and 8 are drawn on **one shared grid** on purpose. Put them
side by side and the layout does not move — only what has been added to it.

## Links from the book

Each chapter README under `examples/` ends with a **Links from the book** list:
every web link printed in that chapter, in order, so you can click instead of
typing. Chapters 1 and 11 have no example folder, so their links are here.

### Chapter 1 links

- Socrates research paper (the architecture behind Hyperscale) — <https://aka.ms/socratespaper>
- Azure SQL Database resource limits — <https://aka.ms/sqldbresourcelimits>
- Azure SQL service level agreement (SLA) — <https://aka.ms/azuresqlsla>

### Chapter 11 links

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

## License

The examples are licensed under the [MIT License](LICENSE).

## Questions, errata, and contributions

For example-code problems or book errata, [open an issue](https://github.com/rgward/sqlhyperscalebook/issues)
with the chapter, script, expected behavior, and sanitized error output.
Do not include credentials, subscription details, or local environment files.
See [CONTRIBUTING.md](CONTRIBUTING.md) for validation commands and contribution
guidelines, and [SECURITY.md](SECURITY.md) for private vulnerability reporting.
