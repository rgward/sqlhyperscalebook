# Figures

Every captioned figure in *Azure SQL Hyperscale Unveiled* is published here,
organized by chapter and named by its book number: `ch02-fig-06-…` is
Figure 2-6. Many figures are hard to read at print size; open the file here to
zoom in. Figures are reproduced as printed.

Back to the [repository README](../README.md).

## Book promotional animation

### Chapter-by-chapter page-turn version

[View or download the chapter flip-through GIF](book-chapters.gif): an animated
book with a cover, a page for each of the eleven chapters, page-turn transitions,
a summary with an attributed excerpt from Arun Ulag's Chapter 11 quote,
and a closing invitation. Each chapter uses its book title and highlights its
key concepts, from the architecture and SQL engine to applications, AI,
observability, security, resiliency, performance, and the Azure platform.
Each chapter has a distinct illustration and accent color: a story timeline,
deployment terminal, architecture topology, real app preview, in-engine RAG
diagram, approval workflow, telemetry chart, security shield, geo-replication
map, compute-stage chart, and Azure ecosystem hub. Charts are illustrative,
not measured performance results.
Chapter 1 honors Project Socrates and the engineering of a new distributed,
cloud-native SQL architecture, tracing SQL Server through Socrates to Hyperscale.
The actual front cover opens the animation, followed by an inside title page.
That title page emphasizes the book and its subject, with a smaller note
explicitly identifying the book examples as AI-assisted creation and guided
learning, not describing Hyperscale itself as built with AI.
The cover note and Chapter 2 illustrate both roles of AI: AI helped build the
examples, and readers use GitHub Copilot and skills to explore and run them,
including guided provisioning, connection, and schema setup.
Chapter pages omit repetitive fine-print notes to keep the animation readable;
the book and repository documentation provide the synthetic-data and
illustrative-chart context.
The architecture page distinguishes HA and named replicas. Brown arrows show
the primary writing to the log service and both the log service and page servers
writing to Azure Storage. Teal arrows show log data flowing from the log service
to HA replicas, named replicas, and page servers; blue arrows show pages flowing
from page servers to the primary and replicas. Read arrows follow the returned
data, not the requests. Shared read lanes keep these paths separate from writes.
Chapter 5 shows
vectors, DiskANN retrieval, and RAG orchestration inside the SQL engine, with
the external model request and response routed through the APIM AI gateway
to and from Foundry.
A separate, blue embeddings connection goes directly between SQL and Foundry,
bypassing APIM.
Chapter 10 highlights serverless, elastic pools, optimized locking, and automatic
index compaction alongside JSON indexing, memory grant feedback, and illustrative vCore scaling
through 8, 16, 40, and 192. The 192-vCore point is not a measured demo stage;
the repository's compute demo remains 8, 16, and 40 vCores.
Chapter 11 surrounds Azure SQL Hyperscale with six talking points: Azure,
Microsoft Foundry, Migrate, Azure App Service, Change Event Streaming, and
Fabric Mirroring.
Chapter 9 separates built-in HA, geo-replication, and point-in-time restore
into three illustrations, with failover and application retries called out.
The PITR caption emphasizes recovery: "Recover from a mistake quickly."
Chapter 7 includes Database Hub, DMVs, and database agents alongside Azure Monitor,
Query Store, and engine events.
Chapter 6 places the handoff agent inside the Ward General app, connected to an
external LLM for orchestration and to SQL MCP for database tool execution.
Human approval gates saving the handoff.
The inside title page and closing page show both the book and code links.
Square format, 640 x 640 pixels, about 69 seconds, looping, no audio.
The GIF uses 96 colors and fewer intermediate turn frames to stay below 5 MB.
It starts slowly, then moves through the chapters faster; the 4K video is unchanged.
The actual front cover remains visible for six seconds and opens smoothly over
2.4 seconds; the inside title spread remains visible for six seconds.
Each chapter remains visible for 2.5 seconds before the page turns.
The summary page remains visible for seven seconds so readers can read the
quote excerpt, attributed to Arun Ulag, Vice President of Azure (title updated
from the book at the author's request).
Its subtitle is "Hyperscale is your database now and for the future."
The camera pulls back as the actual front cover opens against black, then stays
on the open two-page book. Pages lift toward the viewer and turn right to left
around the center spine. The final open-book version is the primary animation;
older chapter animations and opening-preview videos have been removed.
Chapter titles and prose use Georgia serif typography for a printed-book feel;
diagram labels retain sans-serif type for clarity.

The editable generator is [make-book-chapters.py](../tools/make-book-chapters.py).
On Windows, with Python, Pillow, and the Segoe UI and Georgia fonts available,
regenerate it from the repository root:

```powershell
python .\tools\make-book-chapters.py
```

Pass `--preview-dir` with a local directory to also save a storyboard and
page-turn preview outside the repository.

### Book cover

The actual front cover, including the foreword credit, is available as a
[300-dpi PNG](book-cover.png), 2100 x 3000 pixels, extracted from the author's
supplied PDF. The generator uses this PNG directly; neither the cover PDF nor
the full manuscript is distributed with these examples. The older short
promotional GIF has been removed in favor of the chapter animation above.

### Event-screen video

[Download the 4K chapter video](book-chapters-4k.mp4): a silent H.264 MP4 at
3840 x 2160, 25 fps, lasting approximately 146 seconds. It follows the same
chapter sequence as the GIF, with longer holds and page turns for presentations.
The open book and turning pages are rendered natively at 4K
against black, not upscaled from the GIF. Enable repeat/loop in the event's
video player; MP4 does not carry
the GIF's infinite-loop setting. Test playback on the actual event screen
beforehand, since older players may not support 4K H.264.

With FFmpeg and the chapter generator's Python dependencies installed, regenerate using
[make-book-video.ps1](../tools/make-book-video.ps1):

```powershell
.\tools\make-book-video.ps1
```

Use `-FfmpegPath` for an encoder outside PATH and `-OutputPath` for a different
destination. The script renders temporary widescreen PNG frames, removes them
after encoding, refuses to overwrite existing output, and decodes the entire
resulting video to check for errors. It does not transcode the square GIF.

### Camera pullback and open-book spreads

The primary [chapter GIF](book-chapters.gif) and
[4K video](book-chapters-4k.mp4) begin close to the actual cover against black.
The camera pulls back as
the cover opens, then stays on the open two-page book throughout the chapter
sequence. The first inside left page contains the book's exact dedication to the
Microsoft team who brought Project Socrates to life, the technical-reviewer credit
for Kendal Van Dyke, and thanks to quote contributors Shireesh Thota, Slava Oks,
Krystyna Reisteter, Anna Hoffman, Kendal Van Dyke, Naveen Prakash, and Arun Ulag.
The right page retains the cloud-native database theme, SQL Server and AI
highlights, AI-assisted book examples, and book/code links. The full manuscript is
not included in the repository. There is no separate invitation page.
Each chapter has its title and takeaways at the top and a large illustration
across the spread below. Pages lift toward the viewer and turn right to left
around the center spine; the book never transforms into a full-screen slide.
After Arun's summary and the closing links, the cover closes and the camera
returns to its starting view.

The video lasts about 146 seconds. The cover opens for 2.4 seconds; each
chapter turn lasts 1.8 seconds. The first inside spread remains fourteen seconds.
Chapter holds remain six seconds and Arun's summary remains fourteen seconds.
The video runs at 25 fps. The square GIF lasts 68.8 seconds, uses approximately
17 fps for motion, loops continuously, and has no audio. It holds the cover for
six seconds and opens it over 2.4 seconds before accelerating to 0.9-second
chapter turns and 2.5-second chapter holds. The final summary holds for seven
seconds. The closing spread holds for four seconds, the cover closes over
1.2 seconds, and the final cover holds for three seconds. Video-export
timings remain unchanged.
All text stays inside the book; the black background has no captions or overlays.
The book URL, `aka.ms/sqlhyperscaleunveiled`, is printed at the bottom of every
inside page, including both sides of each spread. The introduction and closing
spreads also retain the prominent book and code links. The original cover art
is unchanged.

The 4K video renders the book, typography, diagrams, and rotating sheets from
high-resolution page artwork, rather than switching from low-resolution turns
to high-resolution held pages. The cover uses the high-resolution PNG.
The Unit board uses the original screenshot crop, not the earlier thumbnail;
its detail is still limited by that source image. The shareable GIF is 640 x 640
with a 96-color palette; the generator validates that it stays below 5,000,000 bytes.

### Microsoft product icons

Chapters 2 and 11 use Microsoft's official Azure SQL Database icon, labeled
"Azure SQL Hyperscale" beneath it. The unmodified [source SVG](icons/azure-sql-database.svg)
is `10130-icon-service-SQL-Database.svg` from the official Azure architecture
icons V24 package. Its [transparent 1024-pixel PNG](icons/azure-sql-database.png)
preserves the original colors and proportions and keeps the generator's existing
Python dependencies unchanged.

These Microsoft icons are used under the
[Azure architecture icon terms](https://learn.microsoft.com/azure/architecture/icons/#icon-terms),
which permit use in architecture diagrams, training materials, and documentation.
They are Microsoft assets, not artwork licensed under this repository's MIT license.

| Chapter | Figures |
| --- | --- |
| [Chapter 1](#chapter-1) | 2 |
| [Chapter 2](#chapter-2) | 11 |
| [Chapter 3](#chapter-3) | 12 |
| [Chapter 4](#chapter-4) | 8 |
| [Chapter 5](#chapter-5) | 5 |
| [Chapter 6](#chapter-6) | 11 |
| [Chapter 7](#chapter-7) | 4 |
| [Chapter 8](#chapter-8) | 6 |
| [Chapter 9](#chapter-9) | 5 |
| [Chapter 10](#chapter-10) | 6 |
| [Chapter 11](#chapter-11) | 3 |
| [Diagram sources (SVG)](#diagram-sources-svg) | Editable architecture diagrams |

## Chapter 1

| Figure | Caption |
| --- | --- |
| [1-1](ch01-introduction/ch01-fig-01-the-road-to-azure-sql-hyperscale.png) | The road to Azure SQL Hyperscale |
| [1-2](ch01-introduction/ch01-fig-02-hyperscale-is-built-for-mission-critical-applications.png) | Hyperscale is built for mission-critical applications |

## Chapter 2

| Figure | Caption |
| --- | --- |
| [2-1](ch02-getting-started/ch02-fig-01-azure-sql-in-the-azure-portal.png) | Azure SQL in the Azure portal |
| [2-2](ch02-getting-started/ch02-fig-02-creating-a-hyperscale-database-in-the-azure-portal.png) | Creating a Hyperscale database in the Azure portal |
| [2-3](ch02-getting-started/ch02-fig-03-files-and-scripts-in-vs-code-to-deploy-hyperscale.png) | Files and scripts in VS Code to deploy Hyperscale |
| [2-4](ch02-getting-started/ch02-fig-04-using-ai-assistance-to-make-decisions-like-zone-redundancy.png) | Using AI assistance to make decisions like Zone Redundancy |
| [2-5](ch02-getting-started/ch02-fig-05-confirming-choices-before-deploy.png) | Confirming choices before deploy |
| [2-6](ch02-getting-started/ch02-fig-06-hyperscale-deployment-confirmation.png) | Hyperscale deployment confirmation |
| [2-7](ch02-getting-started/ch02-fig-07-connecting-with-the-mssql-extension.png) | Connecting with the MSSQL extension |
| [2-8](ch02-getting-started/ch02-fig-08-the-azure-activity-log-for-the-hyperscale-deployment.png) | The Azure Activity log for the Hyperscale deployment |
| [2-9](ch02-getting-started/ch02-fig-09-using-ssms-with-azure-sql-hyperscale.png) | Using SSMS with Azure SQL Hyperscale |
| [2-10](ch02-getting-started/ch02-fig-10-using-ghcp-with-your-schema.png) | Using GHCP with your schema |
| [2-11](ch02-getting-started/ch02-fig-11-using-ghcp-with-ssms-to-explore-data.png) | Using GHCP with SSMS to explore data |

## Chapter 3

| Figure | Caption |
| --- | --- |
| [3-1](ch03-architecture/ch03-fig-01-the-socrates-architecture.png) | The Socrates architecture |
| [3-2](ch03-architecture/ch03-fig-02-the-modern-azure-sql-hyperscale-architecture.png) | The modern Azure SQL Hyperscale architecture |
| [3-3](ch03-architecture/ch03-fig-03-looking-at-hyperscale-tiers.png) | Looking at Hyperscale tiers |
| [3-4](ch03-architecture/ch03-fig-04-the-primary-compute-in-hyperscale.png) | The Primary Compute in Hyperscale |
| [3-5](ch03-architecture/ch03-fig-05-limits-for-hyperscale-primary-compute.png) | Limits for Hyperscale Primary Compute |
| [3-6](ch03-architecture/ch03-fig-06-tempdb-files-on-primary-compute.png) | Tempdb files on Primary Compute |
| [3-7](ch03-architecture/ch03-fig-07-the-log-service.png) | The Log Service |
| [3-8](ch03-architecture/ch03-fig-08-page-servers.png) | Page Servers |
| [3-9](ch03-architecture/ch03-fig-09-data-file-storage-in-hyperscale.png) | Data file storage in Hyperscale |
| [3-10](ch03-architecture/ch03-fig-10-hyperscale-replicas.png) | Hyperscale replicas |
| [3-11](ch03-architecture/ch03-fig-11-list-of-hyperscale-replicas.png) | List of Hyperscale replicas |
| [3-12](ch03-architecture/ch03-fig-12-end-to-end-flows-in-hyperscale.png) | End-to-end flows in Hyperscale |

## Chapter 4

| Figure | Caption |
| --- | --- |
| [4-1](ch04-first-app/ch04-fig-01-the-digital-chart-application.png) | The digital chart application |
| [4-2](ch04-first-app/ch04-fig-02-top-of-patient-digital-chart.png) | Top of patient digital chart |
| [4-3](ch04-first-app/ch04-fig-03-bottom-of-the-patient-chart.png) | Bottom of the patient chart |
| [4-4](ch04-first-app/ch04-fig-04-application-architecture.png) | Application architecture |
| [4-5](ch04-first-app/ch04-fig-05-application-source-code-in-the-github-repo-for-the-book.png) | Application source code in the GitHub repo for the book |
| [4-6](ch04-first-app/ch04-fig-06-building-the-application-with-github-copilot-in-vs-code.png) | Building the application with GitHub Copilot in VS Code |
| [4-7](ch04-first-app/ch04-fig-07-how-to-chat-with-your-schema-with-github-copilot.png) | How to chat with your schema with GitHub Copilot |
| [4-8](ch04-first-app/ch04-fig-08-from-the-note-using-regex.png) | From the note using RegEx |

## Chapter 5

| Figure | Caption |
| --- | --- |
| [5-1](ch05-ai-ready-sql/ch05-fig-01-patient-research-in-the-application-using-vector-search.png) | Patient Research in the application using vector search |
| [5-2](ch05-ai-ready-sql/ch05-fig-02-clinical-assistance-in-the-digital-chart.png) | Clinical Assistance in the digital chart |
| [5-3](ch05-ai-ready-sql/ch05-fig-03-application-architecture-with-ai.png) | Application architecture with AI |
| [5-4](ch05-ai-ready-sql/ch05-fig-04-the-hyperscale-vector-architecture.png) | The Hyperscale vector architecture |
| [5-5](ch05-ai-ready-sql/ch05-fig-05-hyperscale-agentic-rag.png) | Hyperscale Agentic RAG |

## Chapter 6

| Figure | Caption |
| --- | --- |
| [6-1](ch06-agentic-ai/ch06-fig-01-llms-and-tools.svg) | LLMs and tools |
| 6-2 | The Model Context Protocol (MCP) — [PNG](ch06-agentic-ai/ch06-fig-02-the-model-context-protocol-mcp.png) · [SVG](ch06-agentic-ai/ch06-fig-02-the-model-context-protocol-mcp.svg) |
| [6-3](ch06-agentic-ai/ch06-fig-03-data-api-builder-dab.png) | Data API Builder (DAB) |
| [6-4](ch06-agentic-ai/ch06-fig-04-using-the-sql-mcp-server-with-dab.png) | Using the SQL MCP Server with DAB |
| [6-5](ch06-agentic-ai/ch06-fig-05-the-ward-general-digital-chart-application-with-ai-agents.png) | The Ward General digital chart application with AI agents |
| [6-6](ch06-agentic-ai/ch06-fig-06-the-agent-chat-feature.png) | The Agent chat feature |
| [6-7](ch06-agentic-ai/ch06-fig-07-the-agent-side-chat-interface.png) | The Agent side chat interface |
| [6-8](ch06-agentic-ai/ch06-fig-08-shift-handoff-candidates.png) | Shift handoff candidates |
| [6-9](ch06-agentic-ai/ch06-fig-09-shift-handoff-approval.png) | Shift handoff approval |
| [6-10](ch06-agentic-ai/ch06-fig-10-shift-handoff-recommendations.png) | Shift handoff recommendations |
| [6-11](ch06-agentic-ai/ch06-fig-11-the-agent-flow.png) | The Agent flow |

## Chapter 7

| Figure | Caption |
| --- | --- |
| [7-1](ch07-observability/ch07-fig-01-azure-monitor-metrics-in-the-portal-for-hyperscale.png) | Azure Monitor metrics in the portal for Hyperscale |
| [7-2](ch07-observability/ch07-fig-02-cpu-spike-for-hyperscale.png) | CPU spike for Hyperscale |
| [7-3](ch07-observability/ch07-fig-03-an-azure-copilot-prompt-for-availability.png) | An Azure Copilot prompt for availability |
| [7-4](ch07-observability/ch07-fig-04-watching-live-data-with-xevent.png) | Watching live data with XEvent |

## Chapter 8

| Figure | Caption |
| --- | --- |
| [8-1](ch08-security/ch08-fig-01-the-wardgeneral-digital-chart-application-with-extra-security.svg) | The WardGeneral digital chart application with extra security |
| [8-2](ch08-security/ch08-fig-02-choosing-a-provider-in-the-digital-chart-application.png) | Choosing a provider in the digital chart application |
| [8-3](ch08-security/ch08-fig-03-shift-handoff-with-rls-applied.png) | Shift handoff with RLS applied |
| [8-4](ch08-security/ch08-fig-04-a-private-link-for-hyperscale.png) | A private link for Hyperscale |
| [8-5](ch08-security/ch08-fig-05-the-flow-of-always-encrypted.png) | The flow of Always Encrypted |
| [8-6](ch08-security/ch08-fig-06-microsoft-defender-for-cloud.png) | Microsoft Defender for Cloud |

## Chapter 9

| Figure | Caption |
| --- | --- |
| [9-1](ch09-ha-resiliency/ch09-fig-01-the-hyperscale-ha-architecture.svg) | The Hyperscale HA architecture |
| [9-2](ch09-ha-resiliency/ch09-fig-02-the-hyperscale-zone-redundancy-architecture.svg) | The Hyperscale Zone Redundancy architecture |
| [9-3](ch09-ha-resiliency/ch09-fig-03-hyperscale-geo-replication-architecture.svg) | Hyperscale Geo-Replication architecture |
| [9-4](ch09-ha-resiliency/ch09-fig-04-the-hyperscale-failover-group-architecture.svg) | The Hyperscale Failover Group architecture |
| [9-5](ch09-ha-resiliency/ch09-fig-05-a-hyperscale-geo-replica.png) | A Hyperscale Geo-Replica |

## Chapter 10

| Figure | Caption |
| --- | --- |
| [10-1](ch10-performance/ch10-fig-01-scaling-the-compute-of-the-wardgeneral-database.png) | Scaling the compute of the wardgeneral database |
| [10-2](ch10-performance/ch10-fig-02-hands-free-data-growth-and-io-for-hyperscale.png) | Hands-free data growth and IO for Hyperscale |
| [10-3](ch10-performance/ch10-fig-03-the-hyperscale-elastic-pool-architecture.svg) | The Hyperscale Elastic Pool architecture |
| [10-4](ch10-performance/ch10-fig-04-json-index-seek-in-hyperscale.png) | JSON index seek in Hyperscale |
| [10-5](ch10-performance/ch10-fig-05-tempdb-spill-due-to-underestimated-memory-grant.png) | Tempdb spill due to underestimated memory grant |
| [10-6](ch10-performance/ch10-fig-06-automatic-index-compaction-in-hyperscale.png) | Automatic Index Compaction in Hyperscale |

## Chapter 11

| Figure | Caption |
| --- | --- |
| [11-1](ch11-azure-best-cloud/ch11-fig-01-why-azure-is-the-best-cloud-for-hyperscale.svg) | Why Azure is the best cloud for Hyperscale |
| [11-2](ch11-azure-best-cloud/ch11-fig-02-the-azure-ai-plane-microsoft-foundry.png) | The Azure AI Plane, Microsoft Foundry |
| [11-3](ch11-azure-best-cloud/ch11-fig-03-using-skills-to-migrate-to-hyperscale-with-dms.svg) | Using skills to migrate to Hyperscale with DMS |

## Diagram sources (SVG)

The architecture diagrams are also published as **SVG** — the source several of
the printed figures were drawn from. They stay crisp at any zoom, and you can open
one and adapt it. Source file names use working numbers; the **Book figure**
column gives the number printed in the book.

| Chapter | Figure | Book figure | What it shows |
| --- | --- | --- | --- |
| 1 | [Timeline](ch01-introduction/ch01-figure-01-timeline.svg) | 1-1 | How Hyperscale got here, from SQL Azure to GA. |
| 3 | [Architecture](ch03-architecture/ch03-figure-01-architecture.svg) | 3-2 | The master figure: all four tiers and the paths between them. |
| 3 | [Primary compute](ch03-architecture/ch03-figure-primary-compute.svg) | 3-4 | The primary replica and its local RBPEX cache. |
| 3 | [Log service](ch03-architecture/ch03-figure-02-log-service.svg) | 3-7 | XLOG — the landing zone, the log broker, and who consumes the log. |
| 3 | [Page servers](ch03-architecture/ch03-figure-page-server.svg) | 3-8 | The 128 GB slices and the `GetPage@LSN` path. |
| 3 | [File and storage](ch03-architecture/ch03-figure-file-storage.svg) | 3-9 | The durable tier, and why you pay on actual allocation. |
| 3 | [Replicas](ch03-architecture/ch03-figure-replicas.svg) | 3-10 | HA replicas, named replicas, and what attaches to what. |
| 3 | [Transaction flow](ch03-architecture/ch03-figure-transaction-flow.svg) | 3-12 | One commit, followed across every tier. |
| 4 | [Application architecture](ch04-first-app/ch04-figure-01-application-architecture-wide.svg) | 4-4 | The Ward General app, and the one connection it makes. |
| 5 | [Application architecture](ch05-ai-ready-sql/ch05-figure-01-application-architecture.svg) | 5-3 | The same app once the engine itself calls out to models. |
| 6 | [Application architecture](ch06-agentic-ai/ch06-figure-01-application-architecture.svg) | 6-5 | The same app once an agent, DAB and the SQL MCP server join it. |
| 6 | [Agent prompt flows](ch06-agentic-ai/ch06-figure-02-agent-prompt-flows.svg) | 6-11 | How a shift handoff moves through the agent, the model, DAB, and SQL. |
| 8 | [Security architecture](ch08-security/ch08-figure-01-application-architecture.svg) | 8-1 | The same app with provider context, Row-Level Security, and the production Private Link path. |

Chapters 4, 5, 6 and 8 are drawn on **one shared grid** on purpose. Put them
side by side and the layout does not move — only what has been added to it.
