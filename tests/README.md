# Book test suite

An automated test suite for every example in this repository. Use it after any
change to confirm the examples still work as the book describes.

| Tier | What it does | Azure | Time | Runs in CI |
| --- | --- | :---: | --- | :---: |
| **Offline** (default) | Checks every script, skill, prompt, and link without connecting to anything | No | About 2–3 minutes | Yes |
| **Live** (`-Live`) | Builds a separate copy of the book's environment, runs every chapter's examples against it, then deletes it | **Yes, billable** | Several hours | No |

```powershell
./tests/Invoke-BookTests.ps1                          # offline tier
./tests/Invoke-BookTests.ps1 -Live                    # live tier: show the plan only
./tests/Invoke-BookTests.ps1 -Live -AcceptCharges     # live tier: run it, then tear down
```

Results go to `tests/results/<tier>-<utc>/` (git-ignored): NUnit XML per test
file, a `summary.txt`, and, for the live tier, every script's full output.

## Prerequisites

| | Offline | Live |
| --- | :---: | :---: |
| PowerShell 7 | ✓ | ✓ |
| [Pester](https://pester.dev) 5.5 or later: `Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -Force -SkipPublisherCheck` | ✓ | ✓ |
| .NET 10 SDK (builds the fake `az` and `sqlcmd` used offline, and the app) | ✓ | ✓ |
| Git | ✓ | ✓ |
| Azure CLI, signed in with `az login` | | ✓ |
| The new [sqlcmd](https://aka.ms/sqlcmd) | | ✓ |
| [sqlsim](https://aka.ms/sqlsimtools), Windows only (Chapter 10 Demos 1 and 2) | | ✓ |

## The offline tier

The offline tier needs no Azure subscription and changes nothing. The
repository-checks workflow runs it on every push and pull request. Its test
files are in [`offline/`](offline/):

| File | What it checks |
| --- | --- |
| `Repository.Tests.ps1` | `tools/validate-repository.ps1` passes. No script has an unguarded Windows-only path or a hard-coded secret. Every SQL file that creates objects keeps the seven-line `SET` preamble. The templates ship only placeholders, and the files readers fill in are git-ignored. |
| `SkillsAndBook.Tests.ps1` | Every Copilot skill has valid front matter, a description of at most 1,024 characters (Copilot silently drops longer ones), and refers only to files that exist. Where Copilot CLI is installed, every skill actually loads. Each of the 20 prompts printed in the book appears in its skill's description and in its chapter README. Each of the book's 130 printed links is listed in the repository. Every Markdown `#anchor` resolves. |
| `PreviewModes.Tests.ps1` | Every billable or destructive script previews by default and makes no change before its gate. A fake, recording `az` confirms that each preview changes nothing, each gate switch (`-Execute`, `-Approve`, `-Apply`) makes exactly the intended change, and each safety guard refuses (wrong database, wrong region, untagged server, and more). |
| `ScriptBehavior.Tests.ps1` | Configuration loading and precedence. The Chapter 7 availability run on macOS/Linux-style paths, with sparse Azure Monitor data and exact Service Health matching. The Resource Graph request with one subscription. The local port helpers. The Chapter 5 environment check. |
| `Coverage.Tests.ps1` | Every `.ps1` and `.sql` example is run by the live tier, either directly or through the script that calls it ([`fixtures/covered-via.json`](fixtures/covered-via.json)). Adding an example without a live test fails here. |

The fake `az` and `sqlcmd` are small .NET programs, built once into
`tests/.cache/` and placed first on `PATH` for the script under test. Scripts
therefore see the same native-command behavior as with the real tools, and the
real Azure CLI is never reached.

## Skill routing evaluation

The offline tier proves each book prompt is *written into* its skill. It can't
prove GitHub Copilot actually *picks* that skill, because that depends on the
model. [`Measure-SkillRouting.ps1`](Measure-SkillRouting.ps1) measures it:

```powershell
./tests/Measure-SkillRouting.ps1                # all 20 book prompts, once each
./tests/Measure-SkillRouting.ps1 -Repeat 3      # three sessions per prompt
./tests/Measure-SkillRouting.ps1 -Chapter 2,5 -Model <model>
```

It first lists the skills Copilot loads (`copilot skill list`) and reports any
repository skill it dropped. Copilot drops a skill silently when its
description breaks the Agent Skills rules; a description over 1,024
characters is the usual cause. It then runs each prompt in a non-interactive
[GitHub Copilot CLI](https://docs.github.com/copilot/how-tos/copilot-cli)
session from the repository root, records the first skill Copilot loads, and
writes `summary.md` and `routing-results.json` to `tests/results/routing-<utc>/`.

- **Safe:** each session has only the `skill` tool, so Copilot can choose a
  skill but can't run a command, edit a file, or reach Azure.
- **Not deterministic:** results can vary between runs and models, so it isn't
  part of CI. Use `-Repeat` to see how stable a choice is.
- **Cost:** one Copilot premium request per session.
- **Fidelity:** Copilot CLI stands in for VS Code agent mode. Both read the same
  `.github/skills` files, but their models and other installed skills can
  differ.

Run it after changing any skill's description. It needs Copilot CLI
installed and signed in.

## The live tier

### Set up `test.env`

```powershell
Copy-Item tests/test.env.template tests/test.env
code tests/test.env
```

[`test.env.template`](test.env.template) documents every value. `tests/test.env`
is git-ignored; it holds a SQL admin password, so never commit it.

The live tier uses **the book's names** (`rg-collierhealth`, `wardgeneral`, and
`collierhealth` plus your suffix for the server) in a **separate** environment.
Use a subscription that doesn't hold your own Collier Health environment. As a
safeguard, the suite refuses to touch a resource group that it didn't create
and tag `booktest=true`.

Values in `test.env` override any `ch04.env` or `ch05.env` you have for the
duration of the run; those files are never changed.

### Run it

Without `-AcceptCharges`, the live tier checks your configuration and sign-in,
prints the plan, and stops. With it, the suite runs Chapters 2 through 10 in
order and then deletes everything it created:

```powershell
./tests/Invoke-BookTests.ps1 -Live -AcceptCharges
```

Each chapter runs the examples the way the chapter README does, including the
preview step before every billable change. It then checks each script's
documented success marker, for example `ALL CHECKS PASSED`, `7 tools`, or
`GeoReplicaVerification=PASS`. If a step fails, the rest of its block is
skipped. If Chapter 2 fails, the run stops, because every later chapter depends
on its database.

| Option | Use |
| --- | --- |
| `-Chapter 2,3,4,5` | Run only these chapters. Each chapter builds on the ones before it, so start at 2, or keep an environment from an earlier run with `-KeepEnvironment`. |
| `-KeepEnvironment` | Leave the environment in place afterwards. **It keeps billing.** |
| `-NoGateway` | Run Chapter 5 without API Management and content safety. This saves the 30–45 minute APIM provisioning and skips the gateway-only proofs. |
| `-ExcludeTag Geo,Tde,Sqlsim,Gateway,LogAnalytics` | Skip optional or long-running parts. |
| `-EnvFile <path>` | Use a different environment file. |
| `-OutputDirectory <path>` | Write results and evidence somewhere else. |

To follow a long step, tail its log:
`Get-Content tests/results/<run>/<chapter>/<step>.log -Wait`.

### Cost, time, and cleanup

> [!WARNING]
> The live tier creates the same billable resources a reader does: an
> 8-vCore Hyperscale database with an HA replica and a named replica, scaled
> to 16 and 40 vCores in Chapter 10, plus a PITR copy, a geo-replica server,
> Microsoft Foundry, API Management, Log Analytics, and a Key Vault. A full run
> takes several hours. Check prices with
> [`estimate-cost.ps1`](../examples/ch02-getting-started/estimate-cost.ps1).

To keep runs shorter and cheaper, the suite embeds 2,000 clinical notes in
Chapter 5 instead of the whole corpus (`BOOKTEST_EMBEDDING_LIMIT=0` embeds
everything, as the book does).

Teardown stops the local apps, removes the Chapter 5 database objects, deletes
and purges the AI resources, and deletes the resource group. A Key Vault with
purge protection (Chapter 8 TDE) stays soft-deleted for its retention period.
That's why each run uses a new vault name. Teardown also restores your Azure CLI
subscription selection.

## Adding or changing an example

1. Add a step to the chapter's `live/NN-*.Tests.ps1`, or, if an existing
   script calls the new one, add it to `fixtures/covered-via.json`.
2. If the script previews a billable or destructive change, add preview,
   gate, and refusal cases to `offline/PreviewModes.Tests.ps1`.
3. Run `./tests/Invoke-BookTests.ps1`, then the live tier for Chapters 2
   through the one you changed. Each chapter builds on the ones before it. For
   example, for Chapter 5:
   `./tests/Invoke-BookTests.ps1 -Live -AcceptCharges -Chapter 2,3,4,5`.

## Layout

```text
tests/
├── Invoke-BookTests.ps1   Runner for both tiers
├── Measure-SkillRouting.ps1  Book prompts through Copilot: which skill it picks
├── test.env.template      Live-tier configuration (copy to test.env)
├── lib/BookTest.psm1      Shared helpers: isolated runs, fake tools, live steps
├── offline/               Offline tier
├── live/                  Live tier: one file per chapter, plus teardown
└── fixtures/              The book's prompts and links, and the coverage map
```
