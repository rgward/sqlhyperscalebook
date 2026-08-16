# GitHub Copilot instructions — Azure SQL Hyperscale book examples

This repository holds the companion code for the Apress book **Azure SQL
Hyperscale Unveiled** by **Bob Ward**. Every hands-on example in the book lives
here, organized by chapter under `examples/`. These instructions apply to **all
chapters and examples** — help a reader run the book's examples successfully and
safely.

## The scenario (book-wide)

The book runs one continuous scenario. **Collier Health** is a (fictional) health
system — the Azure SQL *logical server*, `collierhealth`. **Ward General
Hospital** is its flagship hospital — the Hyperscale *database*, `wardgeneral`.
The story grows from one hospital to a national health system, which motivates
each Hyperscale capability as the book advances. Enterprise-shared resources are
named with `collier`; per-hospital workload resources with `ward`.

## How this repo is organized

- `examples/<chapter>/` — the scripts for each chapter. **Each chapter folder has
  its own `README.md`** with the exact run order and any re-run rules for that
  chapter. **Follow the chapter's README for chapter-specific steps** — do not
  assume one chapter's flow applies to another.
- `.github/skills/` — Copilot **skills** that orchestrate guided flows (for
  example, `deploy-hyperscale` deploys the Ch 2 database). When a reader asks to
  do something a skill covers (e.g. *"deploy my Hyperscale database"*), use the
  skill and follow it one step at a time.

## Conventions to honor (all chapters)

- **PowerShell 7+ (`pwsh`) + Azure CLI (`az`).** Every script in this repo is
  PowerShell and calls `az` for Azure control-plane operations. Don't rewrite
  them as bash or Az PowerShell modules.
- **The reader's resource names live in a file, not in the conversation.**
  Chapters 4 and 5 each ship a `chNN.env.template`. The reader copies it to
  `chNN.env` (git-ignored), fills it in once, and `load-env.ps1` reads it into
  the environment. **Do not interview the reader value by value, and do not go
  discovering names in their subscription and guess which one they meant.** Both
  put their environment somewhere it cannot be reviewed, corrected or reused —
  the chat window — and a wrong guess looks exactly like a right one. Point them
  at the file instead.
- **Scripts still take explicit parameters and environment variables.** The env
  file is the low-friction path, not a requirement; a variable already exported
  in the reader's shell wins over the file. Chapters without a `.env` file are
  driven by environment variables with sensible defaults (`$env:LOC`, `$env:RG`,
  `$env:SRV`). Don't hard-code values into the scripts either way.
- **Never hard-code secrets.** Passwords, tokens, and connection strings come
  from the environment or a prompt — never commit or embed them.
- **Keep the `SET`-options preamble in every `.sql` file.** Each SQL script opens
  with seven `SET` options (`QUOTED_IDENTIFIER`, `ANSI_NULLS`, `ARITHABORT`, …).
  They're required for filtered / indexed-view / computed-column / JSON indexes —
  strip them and `CREATE` fails with **Msg 1934**. Don't remove them, and run
  each file whole.
- **Procs-for-everything.** The schema exposes stored procedures for transactional
  and reusable operations. Call the procedures by name; don't replace them with
  ad-hoc `INSERT`/`UPDATE`/`DELETE` against the tables. Ad-hoc SQL is only for
  genuinely diagnostic/interactive queries (DMVs, Query Store).

## Safety (all chapters)

- **A Hyperscale database bills from the moment it's created** — there's no free
  Hyperscale tier. Mind the meter; each chapter that deploys resources notes how
  to check cost and clean up.
- **All data is synthetic. There is no real patient data (PHI) here — ever.** The
  dataset is AI-assisted and illustrative only; it may not accurately represent
  real medical, clinical, laboratory, or billing data and must never be used for
  clinical or diagnostic purposes.
- **Testing and load tools are for dev/test only** — never point a load generator
  (e.g. sqlsim) at a production database.

## Scope

This repo is the book's **examples**, not a substitute for it. The *why* behind
each choice — architecture, trade-offs, pricing model — lives in the book. Ground
answers in the scripts and each chapter's README; don't invent Azure resources,
guess service limits, or fabricate commands. When unsure, say so and point to the
relevant chapter.
