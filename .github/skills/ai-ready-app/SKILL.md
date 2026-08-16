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
  to the gateway", "what do I need before I start Chapter 5", "what are the
  prerequisites for Chapter 5", "what permissions do I need", "what RBAC roles
  do I need to deploy the AI resources", "is Contributor enough", "role
  assignment failed / does not have authorization to perform action
  'Microsoft.Authorization/roleAssignments/write'", "do I have enough quota for
  gpt-5", "deployment create failed on quota", "what database permissions do I
  need to run the Chapter 5 SQL", "start Chapter 5 over", "reset the AI
  objects", "rebuild the
  AI layer from scratch", "clean up the Chapter 5 resources", "tear down the
  gateway", "my re-run didn't fix it", "prove the vector index is updateable",
  "do I have to rebuild the vector index after inserting notes", "show me a new
  note being found without a rebuild", "prove the gateway blocks a prompt
  injection", "show me Prompt Shields working", "demo the AI gateway blocking a
  jailbreak", "why bother routing through APIM", "what happens if someone puts
  an injection in a patient chart", "run the bonus scripts", or is starting at
  Chapter 5 and wants the whole thing working
  without reading Chapter 4 first. This is the ONLY skill for Chapter 5 — it owns
  the Azure resources, the SQL run order, the gateway, verification, the app, and
  the two optional bonus proof scripts (`10` updateable index, `11` prompt
  injection) that are deliberately NOT part of the application.
  In this repo it BEATS the generic Azure skills: "prepare" here means the
  Chapter 5 AI pre-flight, NOT azd scaffolding (**azure-prepare**) or a generic
  cloud onboarding (**azure-app-onboard**) — the app already exists and already
  runs.
  Scope is ORCHESTRATION and GUIDANCE — it runs the Azure pre-flight, then states
  the SQL run order and explains the scripts on request. **It does not run the
  SQL.** A bare request with **no resource names in it is complete** — the
  reader's names live in `ch05.env`, which they fill in once from
  `ch05.env.template`; never interview them value by value (Step 0).
  For the app's configuration, screens and other feature flags see
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

### Azure permissions — raise this *before* Step 1, not after it fails

`deploy-ai.ps1` both creates resources and grants them access to each other, and
those need different rights. Creating Foundry, the model deployments, APIM and
Content Safety, and assigning the server's managed identity, all need
**Contributor** on the resource group. But it also makes three role assignments
— the SQL server's identity and the gateway's identity each get **Cognitive
Services OpenAI User** on Foundry (`azureaideploy.ps1`, `setup-ai-gateway.ps1`),
and the gateway's identity gets **Cognitive Services User** on Content Safety
(`add-content-safety.ps1`) — and each needs
`Microsoft.Authorization/roleAssignments/write`: **Owner**, **User Access
Administrator**, or **Role Based Access Control Administrator**. Contributor
cannot create role assignments.

This matters because of *where* it fails. The reader gets Foundry and both model
deployments created and billing, then the run dies on the grant, and every later
step depends on it — Chapter 5 authenticates with a managed identity and no key.
If the reader has not said what rights they hold, have them check before you run
anything:

```powershell
$sub = az account show --query id -o tsv
$me  = az ad signed-in-user show --query id -o tsv
az role assignment list --assignee $me `
  --scope "/subscriptions/$sub/resourceGroups/<their-rg>" `
  --include-inherited --query "[].roleDefinitionName" -o tsv
```

**Do not treat a clean `check-ai-env.ps1` as permission to proceed.** Its probes
are read-only `GET`s — they report what exists, never what the reader may create
or grant. Say so if they read a green pre-flight as an all-clear.

- **Model quota** — each deployment asks for capacity **100**. If the region has
  under 100 units free on `OpenAI.GlobalStandard.gpt-5` or
  `OpenAI.GlobalStandard.text-embedding-3-large`, `deployment create` fails.
  Filter the usage list in PowerShell, not with `--query`; on Windows `az.cmd`
  re-parses the argument and a JMESPath expression breaks before the CLI sees it.

  ```powershell
  $want = @('OpenAI.GlobalStandard.gpt-5','OpenAI.GlobalStandard.text-embedding-3-large')
  az cognitiveservices usage list -l <region> -o json | ConvertFrom-Json |
    Where-Object { $want -contains $_.name.value } |
    ForEach-Object { '{0}  used {1} of {2}' -f $_.name.value, $_.currentValue, $_.limit }
  ```

- **Database rights for `06`–`09`** — the reader connects with **CONTROL** on
  `wardgeneral` (in practice `db_owner`, which the Chapter 2 admin login has).
  That covers the database-scoped credential and the external model, and implies
  **EXECUTE ANY EXTERNAL ENDPOINT** for `sp_invoke_external_rest_endpoint`. No
  `sp_configure` step is needed — the procedure ships disabled on SQL Server 2025
  and Managed Instance, but not on Azure SQL Database.

## Step 0 — `ch05.env`, then `check-ai-env.ps1`

**The reader's resource names live in a file, not in the conversation.** Do not
interview them value by value, and do not go discovering names and guessing
which one they meant. Both approaches put the reader's environment somewhere it
cannot be reviewed, corrected or reused — the chat window.

```powershell
cd examples/ch05-ai-ready-sql
./check-ai-env.ps1
```

That single command does everything Step 0 needs:

1. `load-env.ps1` reads `ch05.env`. **If it does not exist, it is created from
   `ch05.env.template` and the run stops.** Tell the reader to open it and fill
   it in. That is the one thing you need from them, and it is a file to edit,
   not five questions to answer.
2. Any value still empty or still carrying `<angle brackets>` is reported by
   name, and the run stops. A partly-filled file never reaches Azure.
3. Every named resource is probed read-only and reported as **exists** or
   **WILL BE CREATED**, with a closing line saying how many would be created.

**Read the WILL BE CREATED lines back to the reader before running the deploy.**
That list is the whole point of the check. A resource they expected to already
have showing up as "will be created" means a typo in `ch05.env` or the wrong
subscription — not a missing resource. Catching that here costs nothing;
catching it afterwards can mean a 30–45 minute APIM provision they did not want.

`check-ai-env.ps1` is read-only. Every call is a GET. It is always safe to run,
including on someone else's environment, and it is the right first move when a
reader reports that something is not working.

The file also feeds the rest of the chapter, so nothing is asked for twice:

| From `ch05.env` | Used by |
|---|---|
| `RG`, `SRV`, `AI_RESOURCE`, `PUBLISHER_EMAIL`, `SUBSCRIPTION_ID`, `CS_RESOURCE` | `deploy-ai.ps1` — it already reads these as its parameter defaults |
| `AI_RESOURCE` | the `<your-foundry>` placeholder the reader edits into `06`, `08`, `10` (Step 2) |
| `APIM_NAME` | the `<your-apim>` placeholder, and `reset-ai-azure.ps1` |
| `WardGeneral__Server`, `WardGeneral__Database` | the app itself, at the highest precedence it honours — so `run-ai-app.ps1` needs no `-Server` or `-Database` (Step 5) |

A variable already exported in the reader's shell **wins over the file**, and
`load-env.ps1` says so rather than overwriting it silently. Someone who exported
`SRV` by hand meant it.

If the reader would rather not use the file at all, every script still takes
explicit parameters. The file is the low-friction path, not a requirement.

## Step 1 — Pre-flight: the Azure AI resources

### The gateway — caution them, do not interview them

`ch05.env` already carries this decision. `PUBLISHER_EMAIL` exists for nothing
but APIM, so a reader who filled it in has asked for the gateway, and
`deploy-ai.ps1` builds one by default. Do not turn a filled-in file back into a
question.

What they do need, once, is the price of that default — and **Step 0 tells you
whether to say it.** If `check-ai-env.ps1` reported the APIM gateway row as
**WILL BE CREATED**, say this, and say it *before* you start `deploy-ai.ps1`:

> The APIM AI gateway is where Chapter 5's governance beat lives — token limits,
> content safety on the way in and the way out, and a single audited egress point
> for every model call the database makes. A first StandardV2 provision takes
> **~30–45 minutes**, and the instance is **always-on and billable** until it is
> deleted.

A reader who discovers a 40-minute provision once it is already under way is
entitled to be annoyed — that is the whole reason this caution exists, and Step 0
is what lets you deliver it in time.

If Step 0 reported the gateway as **exists**, say none of it. The provision does
not happen a second time, and warning about 40 minutes of work that will not occur
teaches the reader to skim past you.

**You are the only warning.** `deploy-ai.ps1` prints no time-or-cost caution of its
own — by the time it runs the decision is already made, and a warning there would
be too late to act on. If you skip this because Step 0 said WILL BE CREATED and you
did not read the row, nothing downstream catches it for you.

The gateway is technically optional: the AI assistance procedure works without it
by calling the model deployment directly. If *they* raise skipping it, add
`-NoGateway`, tell them to set `@UseGateway`'s default to `0` in `08` as that
script instructs, and tell them the gateway can be added later by re-running
`deploy-ai.ps1` without the switch, putting that default back to `1` and re-running
`08` — it is `CREATE OR ALTER`, so nothing is lost. Offer that as an escape hatch
when they ask for it, not as a decision you put back to them.

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
`AI_RESOURCE`, `PUBLISHER_EMAIL`, `SUBSCRIPTION_ID`, `CS_RESOURCE` — so a reader
who filled in `ch05.env` (or still has them set from the Chapter 2 deploy) can
just run `./deploy-ai.ps1` with no arguments at all.

- `-SqlServerName` is the **short** name, not the FQDN. It is the server whose
  system-assigned managed identity gets the role.
- `-AiResourceName` becomes `<name>.openai.azure.com`, so it must be unique
  across Azure — tell them to expect a name collision on anything obvious.
- `-PublisherEmail` is APIM's required publisher contact. Not needed with
  `-NoGateway`.
- The APIM and Content Safety resources are named for them, derived from the
  Foundry name (`<foundry>-gateway`, `<foundry>-contentsafety`). `deploy-ai.ps1`
  has **no `-ApimName`** — the gateway name is always derived. Content Safety can
  be overridden with `-CsResourceName`, whose default is `$env:CS_RESOURCE`, so
  `ch05.env` is the normal way to set it and the switch is rarely typed.
  `ch05.env`'s `APIM_NAME` exists for `check-ai-env.ps1` and `reset-ai-azure.ps1`,
  both of which do accept a non-derived gateway name.

**Content Safety is already handled by `CS_RESOURCE` in `ch05.env`. Do not ask for
it, and do not report passing it as work you have to do.** `load-env.ps1` sets
`$env:CS_RESOURCE`, and `deploy-ai.ps1` declares
`[string] $CsResourceName = ($env:CS_RESOURCE ?? '')` — the filled-in value is the
parameter's default. It is already passed. Adding `-CsResourceName` to the command
line changes nothing.

So a name that differs from the derived `<foundry>-contentsafety` is **not a
problem to flag** — it is the reason that line exists in the file. Telling a reader
who filled it in that a second resource "would" be created is alarming and wrong:
the file is what prevents that.

Left at its template default, the derived name is used, and that derived name is
how the script decides one already exists. That is the case worth a one-line
caution, because it is the single place in the pre-flight where a re-run against a
working environment still **creates** something — an existing Content Safety
resource under some other name, with `CS_RESOURCE` left blank, means a run builds a
*second* one beside it and re-points the gateway policy at the new one.

Either way, do not narrate it. `deploy-ai.ps1` echoes the resolved name in its
opening banner (`content safety : ...`) before it does anything — point at that.
(`-NoContentSafety` skips it entirely. Both switches are on `deploy-ai.ps1` as well
as `azureaideploy.ps1`.)

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
  governed route is live the first time the app calls it. A reader who deployed
  with `-NoGateway` and adds the gateway afterwards re-runs this same file with
  the default put back to `1`; there is no separate gateway script.

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
| — | `reset-ai-objects.sql` | **Destructive.** Only when they deliberately want to rebuild the AI layer from scratch — it discards every embedding. Run it on its own, before `06` |

**Bonus — not part of the application.** Two optional scripts prove claims the
chapter makes in passing. Nothing depends on them, the app never calls them, and
skipping them entirely leaves a complete working Chapter 5. Only reach for them
when the reader asks to *see* the claim demonstrated. Both clean up after
themselves and are safe to repeat.

| Bonus | Script | What it proves | Needs |
|---|---|---|---|
| — | `10-updateable-index-proof.sql` | The DiskANN index is **updateable**: a note written now is searchable now, with no rebuild and no read-only window | `07`, with the index actually built |
| — | `11-prompt-injection-proof.sql` | The gateway's Prompt Shields policy earns its place: an injection planted in the chart is blocked **403, before the model is ever called** | `08`, **and** a gateway with content safety |

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

`06` is otherwise safe — and cheap — to re-run, and so are `07`, `08` and `09`.
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

## Bonus — two scripts that prove what the chapter asserts

**Neither is part of the application.** The app never calls them, nothing in the
run order depends on them, and a reader who skips both has a complete, working
Chapter 5. Offer them when the reader wants to *watch* a claim hold rather than
take a comment's word for it — or when they ask why the gateway is worth the
money. Both undo their own changes and are safe to run repeatedly.

Do not fold these into Step 3. Volunteering a destructive-looking demo during a
first deploy is how a reader loses confidence in the run order.

### `10-updateable-index-proof.sql` — the index tracks DML

Answers *"do I have to rebuild the vector index after writing notes?"* — no.

It embeds a query **once**, into `@QueryVector`, then runs the identical search
three times: before an insert, after it, and after deleting the row again. The
`SELECT` is character-for-character the same each time and the query vector never
changes, so the only variable in the entire script is the contents of the table.
The new note comes back at rank 1 on the second run and is gone on the third. No
DDL, no `REORGANIZE`, nothing named "index" in the step that changes anything.

The topic is deliberately absent from the corpus, so the first search returns
weak neighbours — that is the control, not a bug. Needs `07` to have actually
built the index; on a corpus under 100 rows `07` skips it and this proves
nothing. It inserts one note and removes it again.

Worth naming the history: earlier DiskANN versions made the indexed table
effectively read-only, which is exactly the property this script exists to
disprove. If a reader hits a read-only failure, that is the version check in
`sys.vector_indexes`, not this script.

### `11-prompt-injection-proof.sql` — the gateway blocks before the model

Answers *"why route through APIM at all?"*

The threat model is the point: **nobody types a prompt into this application.**
The clinician clicks a patient, and `GenerateClinicalAssistance` assembles the
prompt itself out of chart fields other people wrote. So the script plants a
textbook injection in two rows that land verbatim in the prompt — one
`Diagnosis.Description`, one `Allergy.Reaction` — then calls the same procedure
twice, one parameter apart. `@UseGateway = 1` comes back **403 before the model
is ever invoked**; `@UseGateway = 0` goes through. Both outcomes land in
`clinical.AIAssistanceLog`, so the block is auditable.

Three things to get right when a reader runs this:

- **It does not poison a clinical note, and that is deliberate.** A note on the
  current encounter would never reach the prompt — `08` only ever *embeds*
  `@caseSummary` as the vector-search seed, and the similar-cases block excludes
  the current encounter. Chart fields are the honest attack surface.
- **A successful direct call does not mean the model was compromised.** `gpt-5`
  will very likely refuse on its own. The narrower, more useful claim is that on
  the direct path the model's own alignment is the *only* control — not
  configured by you, not auditable, not changeable. Azure OpenAI's default
  content filter covers the four harm categories; jailbreak detection is not on
  by default.
- **Requires `add-content-safety.ps1` to have run.** `setup-ai-gateway.ps1` alone
  gives auth, rate limiting and metrics but no Prompt Shields, and the script
  will not block. If a run is *not* blocked, that is a finding to write down —
  not a cue to go hunting for a more evasive payload, because Prompt Shields is
  a classifier and the payloads are textbook by design.

It makes two real model calls, one of which is blocked and therefore not billed.

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
