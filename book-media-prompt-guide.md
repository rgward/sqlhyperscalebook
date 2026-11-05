# From prompts to architecture diagrams and book media

A practical prompt playbook from Bob Ward's *Azure SQL Hyperscale Unveiled*.

This guide shows how an iterative conversation with an AI assistant can produce
architecture diagrams, application illustrations, and promotional media. It
includes selected directions from the book-media conversation, followed by
reusable prompts you can adapt.

The conversation excerpts below are lightly edited for readability, not a
complete transcript. The longer prompt templates are new, reusable examples.

- [The book](https://aka.ms/sqlhyperscaleunveiled)
- [The companion repository](https://aka.ms/sqlhyperscalebook)

## Build the media locally

The finished media is linked from the [figures index](figures/README.md).
The source scripts are also available for adaptation:

- [GIF generator](tools/make-book-chapters.py): on Windows, install Pillow in your
  Python environment and run `python .\tools\make-book-chapters.py` from the repo
  root. It uses the included cover, icons, and application screenshot, plus the
  Segoe UI and Georgia fonts installed with Windows. This replaces the GIF.
- [4K video builder](tools/make-book-video.ps1): with PowerShell 7+, Python,
  Pillow, and FFmpeg available, run
  `.\tools\make-book-video.ps1 -OutputPath .\book-preview-4k.mp4`.
  Use `-FfmpegPath` if FFmpeg is not on PATH. The script refuses to overwrite an
  existing video, removes its temporary frames, and verifies the encoded output.

The video export keeps its longer presentation timing independently of the GIF.

## 1. The approach that worked

Start with the technical story, not the animation.

1. **Provide context.** Identify the audience, the source material, and the result.
2. **Make the architecture correct.** Define components, boundaries, and arrows.
3. **Approve a static visual.** Check labels, spacing, and readability first.
4. **Add presentation behavior.** Specify transitions, pacing, and framing.
5. **Optimize each delivery format separately.** A shareable GIF and an event-screen
   video do not need the same resolution, duration, or file size.
6. **Require evidence.** Inspect the actual exported files, not just the source.

An effective prompt combines:

> Context + source of truth + desired output + constraints + acceptance checks.

## 2. Examples from the actual conversation

The initial request was broad. The useful follow-ups made individual requirements
precise.

| Direction from the conversation | What it accomplished |
| --- | --- |
| "Can you create a GIF about the book?" | Established the creative goal. |
| "For Chapter 6, you need the agent in the app, using SQL MCP with an LLM to orchestrate execution." | Corrected the architecture, not just the labels. |
| "We have more room, but it feels crunched." | Challenged the layout rather than accepting a larger canvas with the same cramped content. |
| "The visuals are a bit fuzzy." | Made output quality an acceptance criterion. |
| "Shouldn't the page turn the other way?" | Caught an animation that looked plausible but behaved incorrectly. |
| "Don't put any text on the background. Everything is in the book." | Established a consistent visual boundary. |
| "Use the official Azure SQL logo." | Replaced a homemade service symbol with an official product icon. |
| "Put Azure SQL Hyperscale under it, not Azure SQL Database." | Kept product labeling aligned with the story. |
| "For PITR, say recover from a mistake quickly." | Shifted the message from the demo's mechanics to the reader's benefit. |
| "Make the GIF faster, but start slow. It is huge; can you make it smaller?" | Separated the opening experience from the later pace and file-size target. |
| "Don't change the MP4, just the GIF." | Protected an approved deliverable while optimizing another. |

**The lesson:** describe what is wrong, explain what must be true, and make one
meaningful correction at a time. You do not need a perfect first prompt.

## 3. Reusable prompt: create an architecture diagram

Use this when the diagram must be grounded in an existing project rather than
invented from a product name.

```text
Create an architecture diagram for [system] for [audience].

First inspect the relevant README files, existing diagrams, and implementation.
Summarize the architecture you found and identify anything uncertain.
Do not invent services, connections, or deployment details.

Show:
- The major components and their responsibilities.
- Application, database, and external-service boundaries.
- The direction and meaning of each connection.
- A legend that distinguishes writes, reads, and control or orchestration.

Keep labels readable at the final viewing size. Use official product icons
where appropriate, preserving their colors and proportions. Keep product
names near the icons and record their source and usage terms.

Produce a static preview before adding animation.
Provide an editable SVG and a high-resolution PNG if the available tools
support those outputs. If an export cannot be produced, say so explicitly.

Validate every arrow against the source material, check for clipped or
overlapping labels, and inspect the actual exported image.
Do not deploy resources or change the running system to draw this diagram.
```

### A concrete Hyperscale example

Start with the
[Chapter 3 README](https://github.com/rgward/sqlhyperscalebook/blob/main/examples/ch03-architecture/README.md)
and the
[published architecture figure](https://github.com/rgward/sqlhyperscalebook/blob/main/figures/ch03-architecture/ch03-figure-01-architecture.svg).

```text
Build a clear Azure SQL Hyperscale architecture diagram using this repository's
Chapter 3 material as the source of truth.

Include primary compute, HA replicas, named replicas, the log service,
page servers, and Azure Storage. Distinguish compute-local cache from the
durable storage tier.

Make arrow semantics explicit. For a diagram showing data flowing:
- Primary compute writes to the log service.
- Log data flows from the log service to HA replicas, named replicas,
  and page servers.
- Pages flow from page servers to primary compute and replicas.
- The log service and page servers write to Azure Storage.

Do not mix read-request arrows with returned-data arrows without labeling them.
Do not add a primary-reading-its-own-log-service path.

Use separate visual lanes for log traffic, page reads, and storage writes.
Keep all labels readable and avoid crossed connectors where possible.
Explain any simplification relative to the published architecture.

Return a static preview for approval before producing other formats.
```

This is an illustration brief, not a request to create replicas or run a workload.

## 4. Reusable prompt: make an agent architecture unambiguous

An "AI" box is not enough. Show where the agent runs and who executes tools.

```text
Create an architecture illustration of the existing application's agent workflow.
Read the application's implementation before drawing it.

Show the agent inside the application boundary.
Show the external LLM outside that boundary.
Show the application's exchanges with the LLM and its calls to SQL MCP tools.
Show the SQL MCP endpoint connecting to the database.

Distinguish proposing an action, approving it, and executing it.
Place the human approval gate before any saved action that requires approval.
Do not imply that the LLM directly writes to the database or bypasses the app.

Use the project's actual component names and connections.
Flag anything you cannot verify rather than drawing an assumed connection.
Provide a readable static diagram first.
```

## 5. Reusable prompt: turn approved visuals into book media

This prompt describes a result. It does not require a particular generator,
image library, or rendering service.

```text
Create a silent book flip-through using the approved cover, chapter titles,
and illustrations I provide.

First show a storyboard and one static spread for approval.
Keep the supplied cover intact. Use a physical book opening and right-to-left
page turns, not a slideshow that stretches into a different layout.

Keep all text on the book's pages, not on the surrounding background.
Make the diagrams large enough to read, and keep their proportions stable
throughout the page turns. Avoid blurry upscaling or wobbling figures.

Include the dedication and credits I supply, the chapter highlights,
and a closing invitation. Do not invent quotations or contributor names.
Put [book URL] at the bottom of every inside page.

Treat GIF and MP4 as separate deliverables:
- GIF: compact and suitable for sharing.
- MP4: native 3840 x 2160, silent, with presentation-friendly holds.

Approve the visual design before rendering the full sequence.
Inspect exported frames, decode the complete outputs, verify their actual
dimensions and duration, and check that every displayed URL resolves correctly.
```

### Optimize the GIF without changing the video

```text
Optimize only the GIF. Do not change or regenerate the approved MP4.

Target a file smaller than 5,000,000 bytes.
Hold the cover for six seconds, open it smoothly, then move through the
chapters faster. Keep a readable closing invitation.

Prefer a balanced reduction in dimensions, palette size, and intermediate
animation frames over illegible text or abrupt transitions.
Preserve the original high-resolution artwork.

Measure the resulting file size and timing. If it misses the size target,
iterate and report the final measured values.
Decode every frame to check the output.
Verify with a file hash that the MP4 is byte-for-byte unchanged.
```

The book's resulting shareable GIF was about 4.82 MB and 69 seconds. Those are
results from this particular artwork, not a guaranteed size for other projects.

## 6. Skills: what they are and which ones to use

A **prompt** describes the current request. A **tool** performs an operation,
such as reading a file or exporting an image. A **skill** supplies a reusable
workflow and its guardrails.

The book repository does **not** currently ship a dedicated architecture-diagram
or media-generation skill. Diagram creation above is a general assistant task
using the available workspace and rendering tools.

The repository does ship skills for running the book's examples. With the repo
open in a compatible Copilot environment, use the natural-language prompts below.
The skill's prerequisites and approval gates still apply.

| Goal | Prompt to try | Repository skill |
| --- | --- | --- |
| Deploy the starting database | "I'd like to deploy an Azure SQL Hyperscale database." | [deploy-hyperscale](https://github.com/rgward/sqlhyperscalebook/blob/main/.github/skills/deploy-hyperscale/SKILL.md) |
| Build and run the patient-chart app | "Build and run the Ward General Hospital app against my Hyperscale database." | [wardgeneral-app](https://github.com/rgward/sqlhyperscalebook/blob/main/.github/skills/wardgeneral-app/SKILL.md) |
| Prepare the Chapter 5 AI experience | "Prepare the application for AI." | [ai-ready-app](https://github.com/rgward/sqlhyperscalebook/blob/main/.github/skills/ai-ready-app/SKILL.md) |
| Build the app-hosted handoff agent | "Build the Chapter 6 agent." | [wardgeneral-agent](https://github.com/rgward/sqlhyperscalebook/blob/main/.github/skills/wardgeneral-agent/SKILL.md) |
| Investigate availability | "Run the Chapter 7 availability investigation for wardgeneral." | [observe-hyperscale-availability](https://github.com/rgward/sqlhyperscalebook/blob/main/.github/skills/observe-hyperscale-availability/SKILL.md) |
| Observe the performance workload | "Run the Chapter 7 performance demo for wardgeneral." | [observe-hyperscale-performance](https://github.com/rgward/sqlhyperscalebook/blob/main/.github/skills/observe-hyperscale-performance/SKILL.md) |

These workflows can operate on Azure resources. Read the chapter README first,
use dev/test environments for workloads, and explicitly approve billable or
disruptive changes. No Azure deployment is needed just to create a diagram.

### Discover skills instead of assuming they exist

```text
Inspect the skills available in this workspace.
Identify which, if any, match my task: [task].
Distinguish repo-provided skills from optional installed capabilities.
Explain which actions are local and which would access or change Azure.
Do not provision resources or run a workload merely to create an illustration.
```

### Turn a proven diagram workflow into a skill

```text
Help me turn this approved architecture-diagram workflow into a reusable
Copilot skill for my project.

First propose its scope and ask me to approve it.
Define the inputs, source-of-truth checks, output formats, and acceptance checks.
Require a static preview before animation and explicit approval before any
cloud changes. Do not bundle deployment or load testing into diagram creation.
Use the customization format supported by my environment.
Do not assume an optional skill-authoring capability is installed.

Keep private file paths, credentials, and project-specific assumptions out of
the reusable instructions.
```

## 7. Review prompts worth keeping

```text
Review this diagram for technical correctness, not just appearance.
Trace every arrow and explain what it represents.
Flag unsupported relationships and misleading application or service boundaries.
```

```text
Review the exported visual at its actual viewing size.
Check label readability, clipping, contrast, spacing, and icon proportions.
Show a preview before making another full animation render.
```

```text
Verify the final deliverables rather than only the source.
Report actual file size, resolution, duration, and playback behavior.
Check all displayed URLs and identify anything that is only text rather than
a clickable hyperlink.
```

## 8. Sharing and ownership

- Provide source material you own or have permission to use.
- Use official product icons under their applicable terms.
- If a supplied PDF contains the whole book, extract only the permitted cover
  or excerpt; do not publish the manuscript.
- Decide which finished assets, editable sources, and build tools to publish.
  Keep local-only material out of Git with deliberate ignore rules.
- Removing a file from the current repository does not erase earlier commits.
- Publicly downloadable GIFs, videos, and diagrams cannot be made technically
  uneditable by removing their build instructions.

**The main takeaway:** the assistant can help create the artifact, but you remain
the technical editor, art director, and final approver.
