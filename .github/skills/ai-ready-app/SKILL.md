---
name: ai-ready-app
description: >-
  Take a reader who has a `wardgeneral` Hyperscale database to the Ward General
  app running in a browser with the Chapter 5 AI features live — the AI
  assistance card on the patient chart and the vector-search Research page. The
  shape is: **pre-flight** (`deploy-ai.ps1` creates the Azure AI resources —
  Foundry, the models, the managed identity and its role, and the APIM gateway),
  then the reader **runs the SQL themselves** (`06` → `07` → `08` → `09`, after
  replacing the endpoint placeholders), then **`run-ai-app.ps1`** builds the
  Chapter 4 app and starts it with the `AiAssistance` flag on. This is the
  Chapter 5 end-to-end path from *Azure SQL Hyperscale Unveiled*. USE WHEN the
  reader says any of: "prepare the application for AI", "prepare the app for
  AI", "make the app AI-ready", "get the Chapter 5 app running", "run the app
  with AI", "I want the AI features working", "turn on AI assistance end to
  end", "deploy and
  run Chapter 5", "pre-flight the Chapter 5 AI resources", "which SQL scripts do
  I run for Chapter 5", "what do I replace in the Chapter 5 scripts", "verify my
  embeddings", "set up everything for Chapter 5", "the AI card is empty / greyed
  out", "the Research page returns nothing", "deploy the Ward General AI layer",
  "set up Foundry for wardgeneral", "build the embeddings", "add the AI
  assistance proc", "put an APIM gateway in front of gpt-5", "add content safety
  to the gateway", "start Chapter 5 over", "reset the AI objects", "rebuild the
  AI layer from scratch", "clean up the Chapter 5 resources", "tear down the
  gateway", "my re-run didn't fix it", or is starting at Chapter 5 and wants the
  whole thing working
  without reading Chapter 4 first. This is the ONLY skill for Chapter 5 — it owns
  the Azure resources, the SQL run order, the gateway, verification and the app.
  In this repo it BEATS the generic Azure skills: "prepare" here means the
  Chapter 5 AI pre-flight, NOT azd scaffolding (**azure-prepare**) or a generic
  cloud onboarding (**azure-app-onboard**) — the app already exists and already
  runs.
  Scope is ORCHESTRATION and GUIDANCE — it runs the Azure pre-flight, then states
  the SQL run order and explains the scripts on request. **It does not run the
  SQL.** For the app's configuration, screens and other feature flags see
  **wardgeneral-app**; to provision the database itself see **deploy-hyperscale**.
  Do NOT use to stand up DAB / the SQL MCP server (Chapter 6) or to deploy
  row-level security (Chapter 8).
---

# Chapter 5, end to end

Three moves: **pre-flight the Azure resources**, **the reader runs the SQL**,
**build and run the app**. This skill owns the order and the hand-offs, not the
work — `examples/ch05-ai-ready-sql/` already ships every script.

All data is synthetic — **no real patient data (PHI), ever.** These scripts create
**real, billable** Azure resources.

## The one rule that governs this skill

**You do not run the SQL. The reader does.**

Chapter 2 established this: the reader runs `01` through `05` in the tool of
their choice because the schema DDL *is* the lesson. Chapter 5 is the same
contract for a stronger reason — here the T-SQL *is* the chapter. The external
model, the vector column, the DiskANN index, the procedure that calls a model and
logs what came back: that is the subject matter. Running it for them hides it.

So: state the order, name the files, explain any of them on request, and stop.
If the reader explicitly asks you to execute a script, that is their call — but
never volunteer it, and never do it as part of the flow below.

## Read this before you do anything else

**There is one Ward General application, and it lives in
`examples/ch04-first-app/`.** Chapter 5 does not ship a copy of it. If a reader
asks for one, or you find yourself about to create one, stop.

`Research.razor` and the assistance card on `Chart.razor` were already compiled
into the Chapter 4 build. They shipped greyed out, waiting for the SQL behind
them to exist. Chapter 5 creates that SQL and flips one boolean. That is the
whole delta.

This is the chapter's argument, not a filing convention: the AI moved **into the
database** — embeddings, vector index, search, the model call, the audit ledger
are all objects in `wardgeneral` — and the application did not change. A second
copy of the app in the Chapter 5 folder would quietly claim you need a new
application to get AI, which is exactly the belief the chapter is dislodging.
Chapter 6 (`AiAgent`) and Chapter 8 (`RowLevelSecurity`) work the same way
against the same build.

`run-ai-app.ps1` resolves `../ch04-first-app` relative to itself. That hop is
stable in the companion repo too, because `publish-examples.ps1` mirrors both
chapters into the same layout.

## The shape: two data paths

Worth stating early, because it explains why the gateway is optional and why one
procedure has a toggle.

- **Embeddings go straight to Foundry.** `AI_GENERATE_EMBEDDINGS ... USE MODEL`
  calls the embedding deployment directly, authenticated by the server's managed
  identity. Batch, internal, no governance surface needed.
- **Clinical assistance — the chat call — can go either way.** The same
  procedure calls `gpt-5` **directly** or through the **APIM gateway**, switched
  by `@UseGateway`. That is the chapter's point: the governed path is a
  deployment choice, not a rewrite.

```sql
EXEC clinical.GenerateClinicalAssistance @EncounterId = 1001;                  -- via gateway
EXEC clinical.GenerateClinicalAssistance @EncounterId = 1001, @UseGateway = 0;  -- direct to gpt-5
```

## Prerequisites (verify, don't assume)

- **PowerShell 7+ (`pwsh`)**, **Azure CLI 2.60+**, `az login` and the right
  subscription (`az account show`).
- **.NET SDK 10+** — the app targets `net10.0`.
- **A SQL client the reader is comfortable in** — the MSSQL extension for VS
  Code, SSMS, Azure Data Studio, or `sqlcmd`. Any of them works; every `.sql`
  file carries the `SET`-options preamble so they behave identically.
- **The `wardgeneral` database exists with schema and seed** (Chapter 2 — see
  **deploy-hyperscale**). `06` embeds `clinical.ClinicalNote`; there is nothing
  to embed without it.
- **The `wardgeneral-research` named replica exists** (Chapter 2's
  `add-replicas.ps1`) if the reader wants the Research page. `09` deploys to the
  primary and the replica reads it; the replica's identity needs Foundry access
  too.

## Step 1 — Pre-flight: the Azure AI resources

### Ask about the gateway first

Before running anything, ask **one** question:

> **Do you want the APIM AI gateway?**
>
> The chapter uses it — it is where Chapter 5's governance beat lives: token
> limits, content safety on the way in and the way out, and a single audited
> egress point for every model call the database makes. It is technically
> optional; the AI assistance procedure works without it by calling the model
> deployment directly.
>
> The cost of saying yes: a first APIM StandardV2 provision takes **~30–45
> minutes** and the instance is **always-on and billable** until you delete it.
>
> **Recommended: yes**, unless you are on a tight budget or want the app on
> screen in the next few minutes.

Do not skip this question and do not answer it for them. It is the one
create-time decision in Chapter 5 that costs real money and real waiting, and a
reader who discovers a 40-minute provision after the fact is entitled to be
annoyed. If they say no, add `-NoGateway`, tell them to set `@UseGateway`'s
default to `0` in `08` as that script instructs, and tell them they can add the
gateway later by re-running `deploy-ai.ps1` without the switch and then running
`10-ai-gateway.sql` — nothing is lost.

### Then run it

```powershell
cd examples/ch05-ai-ready-sql
./deploy-ai.ps1 -SqlServerName <short name of the logical server> `
                -ResourceGroup <their resource group> `
                -AiResourceName <a globally unique Foundry name> `
                -PublisherEmail <their email>
```

Nothing here has a default. That is deliberate: a default name is always
*somebody's* environment, and a reader who forgets an argument would silently
aim at it. Each one has an environment-variable equivalent — `SRV`, `RG`,
`AI_RESOURCE`, `PUBLISHER_EMAIL`, `SUBSCRIPTION_ID` — so a session that still
has them set from the Chapter 2 deploy can just run `./deploy-ai.ps1`.

- `-SqlServerName` is the **short** name, not the FQDN. It is the server whose
  system-assigned managed identity gets the role.
- `-AiResourceName` becomes `<name>.openai.azure.com`, so it must be unique
  across Azure — tell them to expect a name collision on anything obvious.
- `-PublisherEmail` is APIM's required publisher contact. Not needed with
  `-NoGateway`.
- The APIM and Content Safety resources are named for them, derived from the
  Foundry name (`<foundry>-gateway`, `<foundry>-contentsafety`), unless they
  override `-ApimName` / `-CsResourceName`.

**Ask whether they already have a Content Safety resource, and what it is
called.** The derived name is how the script decides one exists. If theirs is
named anything else, a run creates a *second* Content Safety resource beside it
and re-points the gateway policy at the new one — the single place in this
pre-flight where a re-run against a working environment still creates something.
Pass `-CsResourceName <their name>` (or `-NoContentSafety` to leave it alone).
Both are on `deploy-ai.ps1` as well as `azureaideploy.ps1`.

What lands:

| Resource | Why Chapter 5 needs it |
|---|---|
| Foundry (Azure OpenAI) account | Hosts both models |
| `text-embedding-3-large` deployment | What `06` registers as an external model |
| `gpt-5` deployment | What `08` and `10` call for the assistance text |
| System-assigned managed identity on the logical server | The passwordless identity — no key on disk |
| **Cognitive Services OpenAI User** role for that identity | Without it every model call fails auth |
| APIM StandardV2 + content safety | The gateway, unless `-NoGateway` |

Idempotent throughout, so a re-run after a failure resumes rather than starting
over. Every resource above is created only if a probe finds it absent, so a bare
re-run against a complete environment creates nothing. **The one exception is
`-Force`**: it issues an unconditional `DELETE` on the APIM instance before
recreating it, buying another 30–45 minute provision. Never suggest it for a
re-run or a rehearsal — only to recover an APIM instance that is genuinely broken.
It stops at the edge of the database and prints the SQL run order.

Because it only ever creates what is absent, `deploy-ai.ps1` cannot repair a
resource that exists but is wrong — the same limitation the SQL scripts have. The
way out is **`reset-ai-azure.ps1`**, the Azure-side counterpart to
`reset-ai-objects.sql`. It deletes the role assignments, the APIM instance, the
Content Safety account and the Foundry account, in reverse dependency order, and
**purges** each one: Azure AI Services accounts and APIM instances are
soft-deleted, so without a purge the name stays taken and a rebuild silently
recovers the old resource with its old configuration — which reads as "my fix
didn't apply." It never touches the resource group, the logical server or the
`wardgeneral` database.

It supports `-WhatIf`, and that is how a reader should always start. Two switches
matter when advising: **`-KeepFoundry`** rebuilds only the gateway and leaves the
embedding model intact, so the vectors already in the database stay valid and the
reader does **not** re-embed the corpus — this is the right answer whenever the
gateway is the broken part. **`-RemoveServerIdentity`** is off by default because
the identity is shared with other chapters. Deleting the Foundry account is the
expensive path: rebuilding means a fresh APIM provision at 30–45 minutes, and if
the reader also resets the database objects, hours of re-embedding.

### Naming, and how a reader uses their own

Every name the scripts default to is an environment-variable override —
`SUBSCRIPTION_ID`, `RG`, `SRV` (the Hyperscale server), `AI_RESOURCE`,
`AI_LOCATION`. Set the ones that differ in the **same** PowerShell session before
running anything. `RG` and `SRV` are the same variables the Chapter 2 deploy
used, so a session that still has them set is already correct.

The Foundry account is created **`kind=OpenAI`** with a custom subdomain — the
subdomain is what makes Entra token auth possible at all. Note that
`kind=OpenAI` does **not** expose the Content Safety API; that is why content
safety gets its own resource below.

### What the gateway actually does (if they took it)

Worth being able to explain, because it is the chapter's governance beat and it
is genuinely unusual — **there is no app registration anywhere in it.**

- `setup-ai-gateway.ps1` stands up APIM StandardV2 with its own managed
  identity, granted `Cognitive Services OpenAI User` on the Foundry account,
  plus a backend for the chat deployment, a 10K token-per-minute limit, and
  token metrics.
- The inbound policy is `validate-azure-ad-token`, configured to accept **only
  the Hyperscale server's managed identity**, on the **first-party
  `https://cognitiveservices.azure.com` audience** — the exact same token `06`
  and `08` already use to reach Foundry directly. No key, no app registration,
  no Service Tree ID.
- `add-content-safety.ps1` creates a dedicated **`kind=ContentSafety`** resource
  (F0 — free), grants the gateway's identity `Cognitive Services User`, and
  applies one `llm-content-safety` policy with `shield-prompt="true"` and
  `enforce-on-completions="true"`. That is moderation on **both** the prompt and
  the completion. A block returns HTTP **403**.
- `08-ai-assistance.sql` creates a second credential named for the gateway URL
  and builds the procedure with `@UseGateway BIT = 1` as the default, so the
  governed route is live the first time the app calls it.
- `10-ai-gateway.sql` does the same two things for a reader who deployed with
  `-NoGateway` and added the gateway afterwards. Most readers never run it.

`deploy-ai.ps1` runs all three provisioning scripts for you. The pieces are
separate so a reader can add the gateway to a working direct-path deployment
later.

## Step 2 — Tell the reader what to replace

**This has to happen before any SQL runs.** Two values name globally unique Azure
resources, so the scripts cannot ship with working defaults.

| Placeholder | Replace with | In |
|---|---|---|
| `<your-foundry>` | The Foundry resource name from Step 1 | `06`, `08`, `10` |
| `<your-apim>` | The APIM service name from Step 1 | `08`, `10` |

Same `<your-foundry>` value in every file. Each file opens with a **BEFORE
YOU RUN** block naming which placeholders it carries. If the reader named the
embedding deployment something other than `text-embedding-3-large`, that goes in
`06` too.

**If they took `-NoGateway`:** `08` carries a clearly marked note telling them to
change `@UseGateway`'s default from `1` to `0`. Point it out — without that edit
the procedure calls an APIM instance that does not exist, and the failure is a
timeout, not a clear error.

If they ask *why a placeholder and not a variable* — the credential's **name must
exactly equal the endpoint URL**, because SQL matches an outbound URL against a
credential whose name is a URL prefix of it, and a credential name is an
*identifier*. T-SQL has no variables in identifier position, so the value has to
be in the text before the batch compiles. A literal also means the script runs
unmodified in every client, with no substitution mode to switch on.

## Step 3 — Point them at the SQL, in order

Run in the tool of their choice. **In this order** — everything after `06` reads
what `06` creates.

| Order | Script | What it builds |
|---|---|---|
| 1 | `06-ai-embeddings.sql` | Master key, the passwordless credential, the external model, `clinical.ClinicalNoteEmbeddings` as `VECTOR(3072, float16)`, and **the embeddings themselves** |
| 2 | `07-vector-index.sql` | The DiskANN vector index over those embeddings. One statement, its own file — so it can be rebuilt without going near the corpus |
| 3 | `08-ai-assistance.sql` | The gateway credential, then `clinical.GenerateClinicalAssistance` — retrieval, the `gpt-5` call via `sp_invoke_external_rest_endpoint` **routed through APIM**, and the append-only `clinical.AIAssistanceLog` ledger |
| 4 | `09-research-vector-search.sql` | `clinical.SearchSimilarNotes` — retrieval only, no chat step. Deploy to the **primary**; the named replica reads it from shared storage |
| — | `10-ai-gateway.sql` | **Only for a reader who took `-NoGateway` and later provisioned the gateway.** Creates the gateway credential and re-creates the procedure with APIM as its default. Skip it otherwise — `08` already did this |

### Warn them about `06` before they start it

Embedding the full ~60,000-note corpus is roughly **3–3.5 hours** of round-trips
to the model — **longer than a Microsoft Entra access token lives**. Their
connection *will* be dropped part-way through.

Say this up front, because it looks exactly like a failure and is not.
`AI_GENERATE_EMBEDDINGS` does not batch — it is one round-trip per row — so step
4 is a **loop that commits 1,000 rows at a time**, with a `WAITFOR` between
batches to pace against the deployment's token limit. Everything committed
before the drop survives; the most they lose is the batch in flight. The fix is
to reconnect and run the script again: `WHERE NOT EXISTS` means each pass starts
where the last one stopped. Repeat until `verify-embeddings.sql` reports
`MISSING=0`.

Progress prints per batch (`RAISERROR … WITH NOWAIT`), so a long run visibly
advances rather than looking hung.

If they want the app on screen sooner, tell them to skip the loop and run the
`INSERT` once with `TOP (n)`. A few hundred notes is enough for the DiskANN index
in `07` to build (it needs 100 rows) and for both procedures to return real
results.

`06` is otherwise safe — and cheap — to re-run, and so are `07`, `08` and `10`.
Every object they create is created **only if it is absent**; anything already
there is left alone, and each script prints which it did. Against a populated
database a re-run does nothing at all, which is what makes it possible to
rehearse the whole pre-flight sequence without regenerating the corpus.

The corollary matters when a reader is troubleshooting: **re-running cannot
repair anything.** If an object exists but is wrong, running the script again
will skip it and report success. The way to rebuild is `reset-ai-objects.sql` —
the only script in the chapter that drops anything, kept separate and separately
named so it cannot be reached by accident. It removes the procedures, the vector
index, the embeddings table, the external model and both credentials in
dependency order, then the reader runs `06` onward. Do not suggest it casually:
it discards every embedding, and regenerating them is hours of metered calls. It
leaves patient data and the `AIAssistanceLog` ledger untouched.

Rebuilding just the **index** is a different and much cheaper thing — about 43
seconds over 60,000 vectors, and no model calls at all. The `DROP INDEX`
statement sits commented out at the end of `07`; drop it and re-run `07`.

## Step 4 — Verify

**When the reader asks to verify anything about the AI layer, point them here.**

```
verify-embeddings.sql
```

Read-only, safe any time. It reports:

- `NOTES` vs `EMBEDDED` vs `NULL_EMB` vs `MISSING` — **you want `MISSING=0`**
- that `VIX_ClinicalNoteEmbeddings_Embedding` exists
- the byte length of a stored vector — **6,152 bytes** = 3,072 dimensions ×
  float16 (6,144 bytes of payload) **plus 8 bytes** the vector type carries per
  value. The 8 bytes are constant — same for `float32`, same at any dimension —
  and are not documented on Learn; they are observed against a live database.

`MISSING` greater than zero means the corpus is incomplete, not broken. Send them
back to re-run `06`. Its step-4 loop skips what already exists.

For the gateway specifically, the proof is a single `EXEC` — run the procedure
with `@UseGateway = 1` and confirm the answer is a real model response rather
than the procedure's fallback text:

```sql
EXEC clinical.GenerateClinicalAssistance @EncounterId = 1001, @UseGateway = 1;
```

Fallback text means the call never reached the model. Compare against
`@UseGateway = 0`: if direct works and gateway does not, the fault is in APIM —
the policy, the backend, or the managed-identity role — not in SQL.

## Step 5 — Build and run the app with AI on

```powershell
./run-ai-app.ps1 -Server <your-server>.database.windows.net -Database wardgeneral
```

One command, and the order inside it is build-then-run: it calls
`../ch04-first-app/build.ps1`, then `restart.ps1 -Enable AiAssistance`.

Two surfaces light up:

- **`/chart/{EncounterId}`** — the AI assistance card, from
  `clinical.GenerateClinicalAssistance`. Runs on the **primary**: reads the
  chart, embeds it, `VECTOR_SEARCH`es the corpus, calls `gpt-5`, writes an
  append-only ledger row.
- **`/research`** — from `clinical.SearchSimilarNotes` on the
  **`wardgeneral-research` named replica**. Retrieval only: no chat call, nothing
  written.

Variants:

```powershell
./run-ai-app.ps1 -SkipBuild                    # already built
./run-ai-app.ps1 -Clean -Configuration Release
./run-ai-app.ps1 -NoBrowser
```

### The flag is a runtime setting, not a build-time one

If a reader asks whether they need to build *with* the flag: no. `restart.ps1
-Enable AiAssistance` sets the environment variable `Features__AiAssistance`,
which ASP.NET Core reads as the config path `Features:AiAssistance`, and
environment variables outrank `appsettings.json`. Nothing about it is compiled
in. The same binary serves the flag on and the flag off.

What it *does* require is a real **process restart**, because the flags bind once
as `IOptions<FeatureFlags>` at startup. A page refresh does nothing. And
`run.ps1` is worse than useless here: it sees the old process still holding 7170
and just opens a browser at it, so the flag looks broken when it was never read.
That is why `run-ai-app.ps1` delegates to `restart.ps1`, not `run.ps1`.

## Troubleshooting

**The AI card is empty, or Research returns nothing.**
Almost always an unembedded corpus rather than a broken deploy. Both surfaces run
`VECTOR_SEARCH`; against an empty `clinical.ClinicalNoteEmbeddings` they
correctly return nothing. Run `verify-embeddings.sql`. If rows are missing, the
reader re-runs `06` — its step-4 loop resumes from where it stopped.

**The panel is greyed out entirely.**
The flag is off. That means the app was started with `run.ps1` rather than
`run-ai-app.ps1`, or `restart.ps1` was run again without `-Enable` — the switch is
deliberately not sticky, so a bare `restart.ps1` returns the app to its shipped
defaults.

**Auth fails in ~78 ms, before any HTTP call could have happened.**
Too fast to have left the machine, so it is the credential, not Azure. Two
candidates, in this order. First, a placeholder that was never replaced, so the
credential name does not match the endpoint the procedure calls. Second, a
credential missing its audience — "Fail to obtain or decrypt secret for
credential" reads like a decrypt or master-key problem and is not one. It means
SQL does not know which resource to request a token for. The credential must
carry it:

```sql
WITH IDENTITY = 'Managed Identity',
     SECRET   = '{"resourceid":"https://cognitiveservices.azure.com"}'
```

That `resourceid` is the token audience, not the endpoint.

**Auth fails slowly, after a real round trip.**
The role assignment has not propagated, or was never made. Confirm it with
`az role assignment list --assignee <the server's MI object id> --all -o table`
and look for `Cognitive Services OpenAI User`. Propagation can take a few
minutes; a missing assignment never resolves on its own.

**Embeddings come back NULL in bulk while a single row works.**
Throttling, not auth — that split is the tell. `AI_GENERATE_EMBEDDINGS` returns
NULL on a non-200 (an HTTP 429) rather than raising, so a set-based `INSERT`
fails on the NOT NULL vector column. `06` already sets
`PARAMETERS='{"sql_rest_options":{"retry_count":10}}'` on the model, and
`deploy-ai.ps1` pins deployment capacity high enough, so seeing this points at a
pre-existing low-capacity deployment the pre-flight did not create. Check it with
`az cognitiveservices account deployment show ... --query properties.rateLimits`.

**The gateway hangs on roughly half of identical requests.**
Do not hand-rebuild APIM to fix it. A manually reconstructed instance can differ
subtly from the known-good policy and backend wiring, and the hang survives.
Re-run the canonical scripts — `setup-ai-gateway.ps1` then
`add-content-safety.ps1` — which is exactly what `deploy-ai.ps1` does.

**The content safety policy will not apply, or applies and does nothing.**
It was pointed at the Foundry account, which is `kind=OpenAI` and has no Content
Safety API. It needs the dedicated `kind=ContentSafety` resource, which is what
`add-content-safety.ps1` defaults to.

**The chat call errors on parameters that look correct.**
`gpt-5` is a reasoning model: it wants `max_completion_tokens`, not `max_tokens`,
and it rejects `temperature` and `top_p` outright. Budget completion tokens
generously — hidden reasoning draws from the same pool, so a tight limit returns
an empty completion rather than an error.

**Chapter 5 deployed, but the reader wants the chat assistant too.**
That is Chapter 6's `AiAgent` flag and needs DAB running. Different skill —
**wardgeneral-app** for the flag, `examples/ch06-agentic-ai/` for DAB.

## Tearing down

There are two sides to Chapter 5, and they reset independently.

**The SQL objects** — `reset-ai-objects.sql`. Drops the procedures, the vector
index, the embeddings table, the external model and both credentials, in
dependant-first order. It deliberately leaves `clinical.ClinicalNote` (Chapter 2
patient data), the master key, and `clinical.AIAssistanceLog` alone — that last
one is a ledger table and **cannot be dropped and rebuilt**; dropping it soft
deletes it and burns its name and constraints for the life of the database.

**The Azure resources** — `reset-ai-azure.ps1`. Prefer this over ad-hoc `az`
commands, because a bare delete is not enough:

```powershell
./reset-ai-azure.ps1 -WhatIf          # always start here
./reset-ai-azure.ps1 -KeepFoundry     # gateway only; embeddings stay valid
```

APIM instances and Azure AI Services accounts are both **soft-deleted**. Delete
without purging and the name stays reserved, so a later rebuild under the same
name recovers the old resource with its old configuration — which the reader
experiences as "my fix didn't apply." The script purges each one, and captures
the region *before* each delete because purge requires it and it is unreadable
afterwards. Do not suggest a raw `az apim delete` as a substitute.

If the reader only wants to stop paying for the gateway, that is
`-KeepFoundry`: APIM StandardV2 is always-on and billable, the Foundry account
is not billed at rest, and keeping it means the 60,000 embeddings stay usable.

The script never touches the resource group, the logical server or the
`wardgeneral` database — the database is shared across every chapter. Leave the
Foundry account alone unless they are finished with Chapter 6, which reuses it.
