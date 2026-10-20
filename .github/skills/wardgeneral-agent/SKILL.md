---
name: wardgeneral-agent
description: >-
  Evolve the existing Chapter 4 Ward General application into the Chapter 6
  agentic application, deploy the Chapter 6 SQL and DAB/MCP contracts, rebuild
  the shared app, start the MCP endpoint, and restart Ward General with the
  AiAgent feature flag. The Chapter 6 workflow is a two-turn SHIFT HANDOFF:
  find the patients who need one, then prepare an SBAR handoff for a named
  patient and save it through an approval gate. USE WHEN the reader says any of:
  "build the Chapter 6 agent", "evolve the Ward General app", "add Agent Skills
  to Ward General", "add the shift handoff skill", "which patients need a shift
  handoff", "prepare a shift handoff", "add save_handoff", "add the handoff
  candidates query", "set up the Chapter 6 app", "run the Chapter 6 app", "run
  the agentic app", "start the Ward General agent", "enable AiAgent", "set up
  DAB for Chapter 6", "start the Chapter 6 MCP server", "rebuild the app for
  Chapter 6", "test the approval flow", "show me what the agent did", "add the
  agent trace panel". ALSO USE WHEN they say "configure the Chapter 6 app", "where
  does the Foundry endpoint go", "set up appsettings.Development.json", "the
  agent has no model endpoint", "ch04.env is missing after a fresh clone", "I
  cloned this on another machine and nothing runs", "DAB will not start",
  "Audience and Issuer must be set when using a JWT identity Provider", "the
  MCP endpoint publishes generic tools in addition to the seven named tools", "dml-tools is being ignored",
  "which DAB version does Chapter 6 need", "run Chapter 5 and Chapter 6
  together", "enable AiAssistance and AiAgent", or "make the whole app work at
  once". ALSO USE WHEN a Chapter 6 run misbehaves and they say "the handoff
  roster is empty", "no patients need a handoff", "get_handoff_candidates returns
  nothing", "PendingLabCount is always zero", "refresh the shift window",
  "re-anchor the demo data", "refresh and run", "refresh the data and start the
  app", "re-anchor and restart", "I'm back on Chapter 6 a week later", "the demo
  data has gone stale, get it running again", "the seed data is stale", "the
  agent has no tools",
  "show me the agent payload", "what is in the system message", "what is in the
  user message", "what is in the tools array", "how does load_skill appear in
  the payload", "show the handoff conversation payload", "how do the model and
  tools go back and forth",
  "why is place_order not a tool", "what would it take to expose place_order",
  "how would the agent place an imaging order", "add an ordering skill", "what
  is PlaceImagingOrder for", "why deploy a procedure nothing calls", "the
  ordering plumbing", "imaging orders in Chapter 6",
  "nothing answering at localhost:5000", "the pre-flight refuses to start the
  app", "why does run.ps1 need DAB", "the probe shows more than seven tools",
  "the vitals don't trend", "the trends look fake", "every patient looks the
  same", "heart rate jumps back down", "the agent says a patient improved when
  they didn't", "up from / down from is wrong", or "no patient is
  deteriorating". This is the Chapter 6 end-to-end workflow from Azure SQL
  Hyperscale Unveiled: evolve the one shared app in examples/ch04-first-app, add
  clinical.AgentRecommendation and its approval-gated save_handoff MCP tool,
  publish one DAB endpoint over the wardgeneral primary, build, then enable
  AiAgent. Scope is Chapter 6 IMPLEMENT + SQL/DAB SETUP + BUILD + RUN. Do NOT
  create a second Ward General application, deploy the Chapter 5 Azure AI
  resources, point DAB at the named replica, bypass tool approval, or move the
  agent into the hosted Foundry Agent runtime; Chapter 11 owns hosted deployment.
---

# Evolve and run the Ward General agent

Chapter 6 evolves the application the reader built in Chapter 4 and enriched in
Chapter 5. There is still one Ward General application:

```text
examples/ch04-first-app/
```

Make Chapter 6 application changes there, in place. Do not copy the complete
solution into `examples/ch06-agentic-ai/`. That folder owns the Chapter 6 SQL,
DAB configuration, probes, run orchestration, and reader documentation. The
`WardGeneral.Agent` project remains in the shared source tree to avoid copying
the Chapter 4 web and data projects and to preserve one feature-flagged build.

All patient data is synthetic. Never introduce real PHI.

## The workflow

Two turns, and never both in one reply:

1. **Show me the current patients that may need a shift handoff.** The agent
   calls `get_handoff_candidates` once, ranks at most three, and stops.
2. **Prepare patient X for shift handoff.** The agent reads that chart, composes
   four SBAR sections from it, shows them, and proposes `save_handoff`. The
   framework holds the write.

The roster question is answered from one set-based query, not from a chart per
patient. `clinical.GetHandoffCandidates` returns evidence — latest vitals against
the earlier reading in the window, meds started this shift, pending labs and
their age — and the model decides which of it matters. Push the set-based work
into the engine and hand the model a small decided result; an agent that fans out
to N tool calls to reconstruct a `GROUP BY` is doing the database's job badly.

If the trace shows `get_patient_chart` called per patient on turn one, the
runtime skill is not being loaded. Fix that rather than accepting the answer.

## Current implementation status

Do not assume that enabling `AiAgent` proves Chapter 6 is implemented.

Existing:

- `WardGeneral.Agent`, an application-hosted Microsoft Agent Framework client
  connected to one MCP endpoint.
- The runtime Agent Skill at
  `examples/ch04-first-app/src/WardGeneral.Agent/skills/shift-handoff/`.
- The tool-call trace panel (`AgentTrace.cs`, `TracedAIFunction.cs`) and its
  **What the agent did** UI in `AssistantDock.razor`.
- Chart links and follow-up suggestion chips in the dock, both built by the
  application from the encounter ids it parsed out of the reply. After a roster
  turn the chips become one `Prepare a shift handoff for encounter N` per patient
  named; after a successful `save_handoff` they revert to the roster question.
  The model never authors a link or a button that calls it back — keep it that
  way.
- `clinical.AgentRecommendation` + `clinical.SaveShiftHandoff`
  (`11-handoff-contract.sql`) and `clinical.GetHandoffCandidates`
  (`12-handoff-candidates.sql`).
- One `dab-config.primary.json` over the `wardgeneral` primary.
- MAF approval gating on `save_handoff` and the UI round trip.
- The `Features:AiAgent` flag and the chat dock.

The README's **End-to-end proof** is the completion gate. A run is complete only
after it proves zero rows on rejection, one row on approval, and still one row
when the same request key is approved again. Execute that manual proof when the
reader asks for an end-to-end run. Do not invent an evaluation harness or add a
prompt suite unless the reader explicitly asks for one.

## Scope — what Chapter 6 does not build

**There is no ordering system, and no ordering surface.** The assistant prepares
a handoff and stops. If imaging looks warranted it says so in the handoff's
Recommendation and the clinician acts from the chart. No orders page, no
worklist, no status transitions, no cancellation, no results.

**The database plumbing for orders IS deployed, and is deliberately
unreachable.** `14-imaging-order-contract.sql` creates
`clinical.ImagingOrder.RequestKey`, the filtered `UQ_Imaging_RequestKey` index,
and `clinical.PlaceImagingOrder`. Nothing calls them — no DAB entity, no MCP
tool, no application path — so the procedure executes zero times across every
Chapter 6 demo. Deploy it; never wire it up.

That gap is the teaching point, not an oversight. A capability existing in the
database and an agent being permitted to invoke it are separate decisions made
in separate places. The tool inventory is the hard boundary. Human approval then
governs the one write Chapter 6 intentionally offers, `save_handoff`.

If the reader asks what exposing it would take, **explain and stop**: a
`place_order` entity in `dab-config.primary.json`, registration in
`AgentOptions.ApprovalRequiredToolFragments` so MAF holds the call, and a
separate ordering Agent Skill (not merged into the handoff skill — a handoff
describes a patient, an order changes their care). Then the honest limit: even
then an inserted row is a record of an intent, nothing downstream is listening,
and no X-ray happens. Chapter 11 owns the change-event-streaming consumer, also
as discussion rather than construction. **Do not implement any of it.**

Do not propose extra clinical surface. The chapter's claim needs one exercised
write path; more surface moves the reader's attention from the architecture to
clinical realism.

## Sources of truth

Read these before editing:

1. `examples/ch06-agentic-ai/README.md` — reader workflow and locked behavior;
   keep it in parity with this skill.
2. `examples/ch06-agentic-ai/payload.md` — normalized system/user/tool and
  approval exchange for the complete handoff conversation.
3. `examples/ch06-agentic-ai/OBJECT-CATALOG.md` — reader-facing map from the
  Chapter 2–6 database objects to their application, SQL, and MCP callers.
4. `examples/ch04-first-app/README.md` — shared-app build and configuration.
5. `examples/ch04-first-app/src/WardGeneral.Agent/` — current MAF client.
6. `examples/ch06-agentic-ai/11-handoff-contract.sql` and DAB configuration.

Before changing a current Microsoft Agent Framework or DAB API, verify the exact
API against Microsoft Learn or by reflection over the referenced assemblies. Do
not write approval, Agent Skills, or MCP syntax from memory. Two shapes verified
in this repo and worth remembering: `ChatClientAgentOptions` has **no**
`Instructions` property (instructions go on `ChatOptions.Instructions`), and
`ApprovalRequiredAIFunction` derives from `DelegatingAIFunction`, so tracing
composes inside the gate.

## Route by intent

The code for Chapter 6 **ships complete** in `examples/ch04-first-app/src/`. A
reader's request never needs app source edited. Rows marked *maintainer* are for
changing the example itself — use them only when the reader explicitly asks to
modify the code.

| Reader request | Work | Stop after |
|---|---|---|
| **"build the Chapter 6 agent"** (the book's prompt) | Phase 0 (ask only for values missing from `ch04.env` / `appsettings.Development.json`). Then tell the reader what `setup-dab.ps1` will do — install or update the DAB CLI, deploy `11`, `12`, `14`, `13` with go-sqlcmd, validate the DAB config — and run it on their OK. Then `build.ps1`, then Phase 6 with `-Enable AiAssistance,AiAgent`. Do **not** edit app source. | Browser running with the dock |
| Review what Chapter 6 still needs | Read the completion gates and inspect files | Report present/missing evidence |
| Find the WardGeneral.Agent source or ask why it is under Chapter 4 | Point to the shared source tree and explain the ownership split | Reader has the exact path and rationale |
| Explain the agent payload or message/tool exchange | Read `payload.md` and the current agent configuration | Explain the normalized sequence; do not claim it is a raw HTTP capture |
| Find what creates or uses a database object | Read `OBJECT-CATALOG.md`, then verify against the owning SQL or caller when needed | Report the owning chapter, purpose, and caller |
| Configure the app / fresh clone or second machine | Restore `ch04.env` and `appsettings.Development.json` | Both files present and git-ignored |
| *Maintainer:* change the app or runtime skill | Implement only the requested slice (Phase 2) | Focused build for that slice |
| Deploy or explain the SQL and DAB objects | Phase 3 — `setup-dab.ps1`, or explain the contracts | Config validation and direct tool probes |
| Build only | Run the shared solution build | Report build result; do not start services |
| Run Chapter 6 end to end | Complete all gates, then Phase 6's default path (`start-demo.ps1 -Enable AiAssistance,AiAgent`; the book turns on both) | Browser running and smoke evidence captured |
| Run the agent only | As above, restart with `-Enable AiAgent` — only when the reader asks to leave Chapter 5's surface off | Dock present, AI card/Research off |
| Return to Chapter 4 or 5 | Restart without `AiAgent`; leave SQL in place | Confirm the flag-off surface |
| Stop | `./examples/ch04-first-app/shutdown.ps1` (stops the app and DAB) | All owned ports free |

## Phase 0 — Configuration (two git-ignored files)

Chapter 6 needs one setting the earlier chapters did not: an endpoint for the
chat model the agent reasons with. Chapter 5 called its model from inside the
engine, so the application never had to know where it lived.

Both files are git-ignored, so **a fresh clone or a second machine has neither**.
That is not a defect — recreate them.

| file | carries |
|---|---|
| `examples/ch04-first-app/ch04.env` | `WardGeneral__Server` (FQDN), `WardGeneral__Database` |
| `examples/ch04-first-app/src/WardGeneral.Web/appsettings.Development.json` | `Agent:Endpoint`, `Agent:Deployment`, optionally `Research:Database` |

`./examples/ch04-first-app/load-env.ps1` creates `ch04.env` from the template and
stops for the reader to fill in. `appsettings.json` ships `Agent:Endpoint` empty
on purpose; `Agent__Endpoint` as an environment variable also works, and
environment variables outrank both JSON files.

Resolve values from the reader's existing configuration or from resources they
name. Never introduce a default server, Foundry resource, or deployment name. If
exactly one candidate exists in their environment, state it and let them confirm
rather than writing it silently.

There is no key in either file — SQL and the model endpoint are both reached with
`DefaultAzureCredential`, so the reader's identity needs a Foundry data-plane
role on that resource. An endpoint that resolves but returns 401 is a missing
role assignment, not a wrong URL.

## Phase 1 — Establish the baseline

Inspect, do not rewrite blindly:

```powershell
Test-Path examples/ch04-first-app/WardGeneral.slnx
Test-Path examples/ch06-agentic-ai/dab-config.primary.json
Test-Path examples/ch06-agentic-ai/11-handoff-contract.sql
Test-Path examples/ch06-agentic-ai/12-handoff-candidates.sql
Test-Path examples/ch06-agentic-ai/13-refresh-shift-window.sql
Test-Path examples/ch06-agentic-ai/14-imaging-order-contract.sql
```

Build the known baseline before the first application edit:

```powershell
./examples/ch04-first-app/build.ps1
```

A baseline build failure is not a Chapter 6 failure. Capture the raw error and
resolve or report it before editing.

## Phase 2 — Evolve the shared application (maintainer only)

**Skip this phase for every reader request**, including *"build the Chapter 6
agent"*. Everything below already exists in the shipped code; it documents the
design for someone changing the example. Only do this work when the reader
explicitly asks to modify the application or the runtime skill.

Application changes belong under `examples/ch04-first-app/src/`. Keep the core
agent instructions short and always active; put the handoff procedure in a
runtime Agent Skill so MAF advertises it and loads it only for matching work.

Anything that must be true on turn one belongs in `AgentOptions.Instructions`,
not in the skill — the skill body is not in context until the model has already
decided to load it.

The runtime skill must teach the model to:

- Answer one of the two questions per reply, never both.
- Call `get_handoff_candidates` once for the roster, and not open charts to
  rebuild it.
- Rank on **change**, not acuity, and cite the field *and its value* that drove
  each ranking.
- Accept "everyone is stable" as a correct answer.
- Take the encounter id for turn two from its own previous reply, not by
  re-reading the patient's name.
- Build the handoff from the patient's own chart alone, leaving
  `search_clinical_context` uncalled — notes from other encounters are not facts
  about this patient.
- Generate one request-key GUID per handoff and reuse it only on retry.
- Show the four SBAR sections before proposing the write.

The runtime skill must not enforce authorization, route connections, approve an
action, or provide idempotency. Those controls belong in application code, MAF
middleware, and SQL constraints.

Keep every Chapter 6 addition **inert when `AiAgent` is off**. `WardGeneralAgent`
is a lazy singleton resolved only by `AssistantDock`, which renders under
`@if (Features.Value.AiAgent)`, so with the flag off no agent, MCP connection, or
runtime skill is ever constructed. Preserve that: add no eager hosted service,
startup MCP connection, or `IOptions` resolution at startup. This is what lets a
reader return to Chapter 4 without removing code.

**The trace panel.** Tool calls are captured by `TracedAIFunction`, a
`DelegatingAIFunction` wrapper, into an `AgentTrace` held per conversation and
reached through an `AsyncLocal`. The `AsyncLocal` is required: tools are built
once and shared across conversations, so the wrapper cannot capture a
conversation in a closure. Wrap tracing **inside** the approval gate
(`new ApprovalRequiredAIFunction(new TracedAIFunction(tool))`) so an approved
write is traced too, and arm the trace on both `AskAsync` and
`RespondToApprovalAsync`. Clear it at the top of each turn so a reply shows only
its own work.

After the first substantive application edit, immediately run the focused build:

```powershell
./examples/ch04-first-app/build.ps1
```

Do not continue to another implementation slice until that build passes.

## Phase 3 — Add the database contracts

For the book's prompt (*"build the Chapter 6 agent"*), the skill applies these:
tell the reader what will run, then run `setup-dab.ps1` on their OK. If the
reader wants to run the T-SQL themselves, use `setup-dab.ps1 -SkipSql` (it still
installs the DAB CLI and validates the config) and give them the order below.

Run the scripts in numeric order so the deployed contracts match the DAB
configuration:

| script | adds |
|---|---|
| `11-handoff-contract.sql` | `clinical.AgentRecommendation`, the `Ward General Assistant (system)` provider row, `clinical.SaveShiftHandoff`; removes obsolete Chapter 6 wrapper procedures on upgrade |
| `12-handoff-candidates.sql` | `clinical.GetHandoffCandidates` |
| `14-imaging-order-contract.sql` | `clinical.ImagingOrder.RequestKey`, `UQ_Imaging_RequestKey`, `clinical.PlaceImagingOrder` — **deployed, never called.** No DAB entity, no MCP tool, no caller |
| `13-refresh-shift-window.sql` | re-anchors the demo's shift window to now; adds genuinely outstanding labs; reshapes in-window vitals so they trend |

Deploy order is `11`, `12`, `14`, then `13`. The refresh script runs last because
it re-anchors the demo window to the moment it runs.

`setup-dab.ps1` deploys all four in this order. It
runs them with **go-sqlcmd** (`sqlcmd` v1.x), whose bare `-G` resolves
`DefaultAzureCredential` — the same passwordless identity the app and DAB use.
**The legacy ODBC `sqlcmd` is not interchangeable:** its `-G` attempts Entra
*interactive* auth and needs ODBC 17.2+. Both install as `sqlcmd`, and on Windows
the ODBC build sits on the machine PATH, which wins over the user PATH — so the
script resolves `-SqlCmd`, then `$env:SQLCMD`, then
`%LOCALAPPDATA%\Programs\sqlcmd`, then `C:\Program Files\sqlcmd`, then `PATH`,
skipping any candidate whose `--version` fails. That check succeeds only on
go-sqlcmd.

If nothing resolves it **fails**. Do not work around it by reaching for the ODBC
`sqlcmd` or for sqlsim — sqlsim is Chapter 10's load driver, not Chapter 6's SQL
runner. Install go-sqlcmd (`winget install --id Microsoft.Sqlcmd`, or unzip a
release and set `SQLCMD`). `-SkipSql` is the supported way to opt out and run the
scripts yourself.

The failure is a fail rather than a warning on purpose: a skipped deploy leaves
setup reporting success with none of the contracts present, and that resurfaces
much later as an agent with missing tools — which reads as a model problem.

**Chapter 6 does not deploy `clinical.SearchSimilarNotes`.** That procedure backs
`search_clinical_context` and belongs to Chapter 5
(`09-research-vector-search.sql`). Chapters 4 and 5 are prerequisites. Do not add
`09` back into `setup-dab.ps1`: it cannot run without the external model from
`06` and the vector index from `07`, neither of which Chapter 6 deploys either,
so re-running one link of that chain protects nothing while overwriting a
Chapter 5 object from a Chapter 6 script. A reader who skipped Chapter 5 gets
six working tools and a `search_clinical_context` that fails at call time naming
the missing procedure.

**On a second machine, do not tell the reader to re-run Chapter 4 or Chapter 5.**
Their output lives in two shared places — the `wardgeneral` database and their
Azure resources — so it is already present. Only local artifacts need recreating:
`ch04.env`, `appsettings.Development.json`, the build, the HTTPS dev certificate,
and a SQL firewall rule for the new egress IP. When in doubt, query the database
instead of assuming:

```sql
SELECT CASE WHEN OBJECT_ID('clinical.SearchSimilarNotes','P') IS NULL
            THEN 'MISSING - run Chapter 5' ELSE 'present' END;
```

Required of every Chapter 6 write procedure:

- Typed inputs, no dynamic SQL.
- Validation that the encounter is active and the system provider exists.
- One atomic `INSERT ... SELECT` with a `NOT EXISTS` guard on the request key;
  no outer transaction, because a single DML statement is already atomic.
- A database uniqueness rule on the request key before retry-safe idempotency is
  claimed. An application check alone loses the race.

Scripts must be rerunnable, and must not alter existing columns, constraints, or
Chapter 2/4/5 views.

Direct SQL validation must prove:

- Valid input inserts one row and returns its identity.
- Invalid input inserts zero rows.
- Reusing the request key cannot insert a second row.

Known limitation to state rather than hide: `clinical.Diagnosis` has no
timestamp, so `12-handoff-candidates.sql` approximates "added recently" by
identity order. The script documents this. Do not fabricate a date column.

`13-refresh-shift-window.sql` is a pre-flight, not a contract, and it is required
before the two-turn workflow will demonstrate anything. The Chapter 2 seed places
active admissions a few hours before the moment it runs, and
`clinical.GetHandoffCandidates` looks back twelve hours — so on any day after
seeding day the first turn correctly returns an empty roster. The script measures
the gap and shifts activity on **active** encounters forward by it, in one
transaction, leaving discharged encounters untouched because those are the
historical note corpus Chapter 5 searches. It also creates labs in `Ordered` or
`Collected` status, without which `PendingLabCount` is structurally always zero
— every seeded lab is `Resulted`.

Its third part reshapes vitals, and that part is not cosmetic. Chapter 2 emits
vitals as a counter — heart rate climbs 117, 118, 119, wraps to 100, climbs again
— while `clinical.GetHandoffCandidates` reports the latest reading against the
earliest one still inside the window. On counter data that pair is an artifact of
where the window starts, and a wrap inside the window inverts it, so a patient who
never changed reads as dramatically improved. The script rewrites in-window
readings as a line from a per-encounter baseline plus jitter, assigning roughly a
fifth of encounters a deteriorating course, a fifth improving, the rest stable.
Values are absolute, so rerunning recomputes the same line rather than compounding
drift.

Two choices there are load-bearing, and a well-meant "simplification" breaks the
demo. The course key `(EncounterId / 5) % 5` deliberately differs from the
`EncounterId % 5` used for pending labs, so the deteriorating patients are not the
same patients with an outstanding lab — two signals that always agree teach the
reader nothing about weighing evidence. And the cohort is a fifth rather than a
handful because `clinical.GetHandoffCandidates` does **not** rank: it returns the
ten most recently active encounters, not the ten sickest, so hand-picking three
sick patients would very likely put none of them in front of the model.

If a reader says the agent's trends look wrong, fabricated, or identical across
patients, the answer is almost never the prompt, the skill, or the procedure — all
four of those are correct on counter data, which is exactly the problem. Verify by
reading the earlier/latest pair straight from `clinical.Observation` for one
encounter before saying anything about the model. Script `13`'s own verification
block prints that pair per course for heart rate, SpO2 and temperature.

When a reader reports an empty roster, do not debug the prompt or the procedure.
Measure first: read the newest `RecordedAt` on `clinical.Observation` for active
encounters. If it is more than twelve hours old, the data is stale and the fix is
to rerun script `13`, which is idempotent and prints `Window already fresh` when
there is nothing to do.

## Phase 4 — Publish and validate the MCP endpoint

One DAB configuration carries one connection string, so one DAB process reaches
one database. Chapter 6 uses **one**, over the primary:

```text
dab-config.primary.json    port 5000   wardgeneral

  reads   get_patient_chart, get_patient_chart_by_bed, search_encounters,
          get_handoff_candidates, search_clinical_context, clinical_assistance
  writes  save_handoff      [approval-gated]
```

Do not point DAB at `wardgeneral-research`, and do not add a second endpoint. The
Chapter 5 Research page reaches the named replica on its own ADO.NET connection
(`WardGeneralConnectionFactory.CreateResearch`), independently of DAB and of the
agent. If asked to "route the agent to the replica", say that this was decided
against and that the replica path is Chapter 5's, not Chapter 6's.

Entities are named in literal snake_case so the emitted MCP tool name matches
the chapter and the runtime skill regardless of DAB's naming convention. The
configuration declares only the seven procedures the agent may call. Never
expose free-form SQL or a generic execute-procedure tool.

Start it (for the reader's normal run, `start-demo.ps1` in Phase 6 does this in
the background; run it directly only when debugging DAB):

```powershell
./examples/ch06-agentic-ai/run-dab.ps1
```

`dab start` has **no** `--port` switch. `run-dab.ps1` sets the port through
`ASPNETCORE_URLS` and passes `--no-https-redirect`; do not invent CLI flags for
it. The script also runs `dab validate` before starting, so a config error
surfaces on its own rather than inside startup output.

**DAB must be 2.0.0 or later, and this is enforced, not advised.** `runtime.mcp`
and its `dml-tools` switch do not exist in 1.x, and `dml-tools: false` is what
bounds the tool surface to seven. On a 1.x CLI the config passes schema
validation and *then* the engine dies with `Audience and Issuer must be set when
using a JWT identity Provider` — against a config whose provider reads
`Unauthenticated`. Do not go looking for a JWT problem: there isn't one. Both
`setup-dab.ps1` and `run-dab.ps1` now check the version and name it. The fix is
`dotnet tool update --global Microsoft.DataApiBuilder`.

Probe the inventory directly before involving the model:

```powershell
./examples/ch06-agentic-ai/probe-mcp.ps1 -Detailed
```

Evidence must show:

- Seven tools — six that are not approval-gated and `save_handoff`, and nothing
  else. (`clinical_assistance` is a GraphQL mutation that writes an audited
  record, so "six reads" is loose: it is six *non-gated* tools.)
- Tool descriptions that distinguish this patient's current chart from the
  historical corpus of other encounters.
- `save_handoff` returning the procedure's narrow result shape.

Seven is the whole inventory only because `dab-config.primary.json` sets
`runtime.mcp.dml-tools` to `false`. DAB publishes its seven generic tools **on by
default**, and `execute_entity` among them can call a stored procedure by name —
including the procedure the application approval-gates, which is a path around
the gate. A probe returning more than seven means that setting regressed. Fix the
configuration; an application-side tool allow-list does not close this, because
it is a configuration problem rather than a tool-name problem.

The same reasoning forbids adding a table or view entity. Chapter 6 exposes only
named stored-procedure contracts and deliberately runs unauthenticated under one
DAB identity with unrestricted access to synthetic patients. Chapter 8 owns the
authenticated DAB and Row-Level Security design.

The tool inventory is the security surface, and prose is not. If a tool is wrong,
fix the configuration rather than compensating in the prompt.

The application reaches the endpoint through `Agent:McpUrl` in `appsettings.json`.
Resolve the reader's server from their existing configuration
(`WardGeneral__Server` in `examples/ch04-first-app/ch04.env`) or require
`-Server`. Never discover a server and guess which one they meant, and never
introduce a default server name.

## Phase 5 — Enforce approval in MAF and the UI

Wrap `save_handoff` with the current MAF approval-required mechanism. Read tools do
not need human approval — a prompt the reader clicks through on every read is a
prompt they stop reading.

The approval round trip must:

1. Pause before DAB invokes SQL.
2. Surface the tool name and every proposed argument verbatim, so the clinician
   approves what the model actually asked for rather than a paraphrase.
3. Bind approval/rejection to the exact pending tool call in the same agent
   session.
4. Send the framework approval response, not a conversational `yes`.
5. On rejection, execute no SQL write.
6. On approval, execute once and report the returned `RecommendationId`.

**Identity in Chapter 6 is the system provider, not a signed-in clinician.**
There is no authentication yet, so `clinical.SaveShiftHandoff` resolves the
`Ward General Assistant (system)` row internally. No provider identity crosses
the prompt, MCP contract, or application call. `ProposedById` remains `NOT NULL`
with an FK because a handoff with no author is not a handoff; the system row
records something true rather than forging a clinician or leaving the column
blank.

Do not require a provider selection, and do not require Chapter 8's
`RowLevelSecurity` flag, to save a handoff. The "Viewing as" selector stays gated
on `RowLevelSecurity` in `Home.razor` — leave it there. Chapter 8 owns Entra
authentication, trusted provider mapping, DAB session context, and Row-Level
Security; it replaces this Chapter 6 identity boundary rather than changing one
model argument.

A prompt instruction is not an approval control. Do not auto-approve the write
and do not substitute a custom boolean that bypasses MAF's pending tool-call
contract.

## Phase 6 — Build and run

`run.ps1` uses `dotnet run`, so a restart already compiles the current sources.
Build explicitly anyway: it reports compiler errors on their own instead of
burying them in startup output.

Stop the running app before a clean build, because Windows retains locked
assemblies while the app is running:

```powershell
./examples/ch04-first-app/shutdown.ps1
./examples/ch04-first-app/build.ps1 -Clean
```

### Start DAB and the app — the default path

DAB must keep running while the reader uses the app, and an agent-attached
process can die with the chat session. Use the Chapter 4 launcher, which starts
both as background processes that outlive the terminal and the chat, waits for
each to answer, and **returns**:

1. Firewall first, in chat. `start-demo.ps1`'s pre-flight asks about a missing
   firewall rule with a terminal prompt the reader may never see. Check it
   yourself — this changes nothing:
   ```powershell
   ./examples/ch02-getting-started/preflight-firewall.ps1 -Server <short-server-name> -Yes -WhatIf
   ```
   If it reports **NOT allowed**, show the proposed change and ask the reader.
   Only on an explicit yes, rerun it with `-Yes` (no `-WhatIf`).
2. Start everything:
   ```powershell
   ./examples/ch04-first-app/start-demo.ps1 -Enable AiAssistance,AiAgent -SkipFirewall
   ```
   It starts DAB on 5000 if nothing answers there, probes the MCP endpoint, runs
   the app pre-flight, starts the app, health-checks it, and opens the browser.
   DAB's first bind can take a couple of minutes (Entra token plus schema
   metadata for every entity); the script waits up to 180 seconds.
3. Report the URL and the log folder, `%LOCALAPPDATA%\WardGeneral\logs`.

**Stop** is `./examples/ch04-first-app/shutdown.ps1` — it stops the app and DAB.

**Returning on a later day:** the shift window will have aged out. After the
same firewall check, run the one command that refreshes the window and then
starts both in the background:

```powershell
./examples/ch06-agentic-ai/refresh-and-run.ps1 -Detached -SkipFirewall
```

### Foreground path — debugging DAB startup

Use this only when the reader is debugging DAB. Start DAB using the Chapter 6
script in its own terminal. It is a long-running process; keep its
terminal/process identifier so it can be stopped later. Give it time to bind:
it acquires an Entra token and reads schema metadata for every entity at startup,
so on a slow link the first bind can take a couple of minutes. Wait for the
listening line rather than concluding it failed.

Only after the MCP probe passes, restart the shared app with the feature flags.
The book runs Chapter 6 with **both** Chapter 5's `AiAssistance` and the new
`AiAgent` — `-Enable` is the complete list, so naming only `AiAgent` would switch
the Chapter 5 AI card and Research page off:

```powershell
./examples/ch04-first-app/restart.ps1 -Enable AiAssistance,AiAgent
```

When the reader is returning to Chapter 6 on a later day — which is most of the
time after the first sitting — prefer the wrapper, because a bare restart leaves
them with an aged-out window and a first turn that correctly finds nobody:

```powershell
./examples/ch06-agentic-ai/refresh-and-run.ps1
```

It runs `13-refresh-shift-window.sql`, then hands off to `restart.ps1`. It
defaults to `-Enable AiAssistance,AiAgent`; pass `-Enable AiAgent` only if the
reader wants the agent alone. `-SkipRefresh` restarts without touching data. It resolves
go-sqlcmd the same way `setup-dab.ps1` does and fails with the same guidance. It
does **not** start DAB — the pre-flight below already catches that and names
`run-dab.ps1`, and duplicating the check would put two different messages on the
same fault.

**Expect an interactive prompt.** `restart.ps1` asks for approval before it adds
or updates the server firewall rule for the current client IP. Run it where that
prompt is visible and answer it, or pass `-SkipFirewall` when the rule already
exists; `-SkipPreflight` passes through as well. Launched in a background or
detached terminal it does not fail - it sits there looking idle, which reads as a
hang.

That ordering is enforced, not merely advised. With `AiAgent` set,
`preflight-run.ps1` probes `Agent:McpUrl` and **fails**, naming `run-dab.ps1`,
when nothing answers — an agent that starts with no tools sends the reader to
debug a prompt when the real fault is an unstarted process. The check is skipped
entirely when the flag is off, so Chapter 4 and Chapter 5 runs are unaffected. It
warns, rather than fails, on a tool count other than seven.

When the reader wants the whole application — Chapter 5's assistance card and
Research page alongside the Chapter 6 dock — name both flags in one restart:

```powershell
./examples/ch04-first-app/restart.ps1 -Enable AiAssistance,AiAgent
```

`-Enable` is a complete, non-sticky list, so the next restart's list is the whole
truth. Running both is also the clearest view of Decision B: the Research page
reaches the named replica on its own connection, tagged
`ApplicationName=wardgeneral-research` in `sys.dm_exec_sessions`, while every
agent tool goes through DAB to the primary. Chapter 5's `06`–`09` must be
installed as well as Chapter 6's `11`–`13`; a missing Chapter 5 object fails the
assistance card while the agent keeps working, because the paths share nothing
but the server.

A feature flag reveals the implementation; it does not create it. If the runtime
skill, the endpoint, the procedures, or the approval handler is missing, stop and
name the missing gate rather than presenting the chat icon as success.

## Phase 7 — Required end-to-end proof

Use synthetic data. No provider selection and no `RowLevelSecurity` flag are
required — `AiAgent` alone is enough, and the handoff is attributed to the system
provider.

1. Ask: **Show me the current patients that may need a shift handoff.**
2. Open the trace panel. Confirm `get_handoff_candidates` ran exactly once, and
   that no per-patient chart calls were made.
3. Confirm each ranked patient carries a named field and its value.
4. Name one of them: **Prepare patient X for shift handoff.**
5. Confirm `get_patient_chart` ran for that encounter, and that
   `search_clinical_context` did **not** run — a handoff is built from this
   patient's chart alone.
6. Confirm the four SBAR sections appear before the approval card.
7. Reject and prove zero inserted rows for that request key.
8. Repeat with a new request key, approve, and prove exactly one inserted row.
9. Approve once more with that same request key and prove the count is still one.
10. Read the reply that follows a successful save. It must report the save in the
    past tense with the returned `RecommendationId` and `Proposed` status. A
    closing line that offers to save the handoff **after** the row exists is a
    failure: it tells the clinician the opposite of what happened and invites an
    approval they already gave.

A plausible answer without the required tool trace is a failure. An approved
conversation without exactly one durable row is a failure.

## Rollback — returning to Chapter 4 or Chapter 5

Three layers behave differently — be precise about which one they are asking
about.

**Application code — nothing to remove.** `-Enable` is a complete, non-sticky
list, so a restart that omits `AiAgent` clears it:

```powershell
./examples/ch04-first-app/restart.ps1                        # Chapter 4 surface
./examples/ch04-first-app/restart.ps1 -Enable AiAssistance   # Chapter 5 surface
```

The Chapter 6 code stays compiled in but never runs. Also stop DAB — with the
flag off nothing calls it.

**SQL objects — safe to leave in place.** Everything Chapter 6 adds is backward
compatible; Chapters 4 and 5 run unchanged against it. Remove only on explicit
request, in dependency order:

```sql
DROP PROCEDURE IF EXISTS clinical.GetHandoffCandidates;
DROP PROCEDURE IF EXISTS clinical.SaveShiftHandoff;
DROP TABLE     IF EXISTS clinical.AgentRecommendation;
DELETE FROM ops.Provider WHERE FullName = N'Ward General Assistant (system)';
```

The system provider row goes *after* the table it is referenced from; the foreign
key holds it in place while any handoff still exists.

**Data.** Handoffs are self-contained — `clinical.AgentRecommendation` holds
nothing but agent-created rows, so dropping the table removes them all and
touches no seed data.

**Source rollback.** If the reader wants the pre-Chapter-6 source itself, that is
a Git operation on their clone, not a repository script. Confirm their branch and
uncommitted work before suggesting any revert, and never discard uncommitted
edits on their behalf.

## Completion report

Report concrete evidence, not only actions:

- Shared solution build result.
- Runtime skill discovered and loaded.
- MCP tool inventory.
- Trace evidence for both turns, including the single `get_handoff_candidates`
  call.
- Rejection row delta: zero.
- Approval row delta: exactly one.
- Returned and persisted `RecommendationId`.
- App URL and enabled feature flag.

If live authentication prevents SQL or DAB validation, say exactly which check
was not completed and preserve the successful local build evidence separately.
