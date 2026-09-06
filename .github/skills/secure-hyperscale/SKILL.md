---
name: secure-hyperscale
description: >-
   Run the Chapter 8 Ward General security example: install
   SESSION_CONTEXT-driven Row-Level Security and restart the existing app with
   its RowLevelSecurity feature flag.
    USE WHEN the reader says "run the Chapter 8 security example", "run the
   Chapter 8 RLS app demo", "run the Chapter 8 RLS app demo from a clean state",
    "enable RLS in Ward General", or "show the Viewing as security demo". Do not
   create roles, enforce Entra-only authentication, provision CMK or Private
   Link, classify data, generate Defender alerts, or create or inspect ledger
   objects. Azure SQL Database auditing is owned by the separate
   audit-wardgeneral skill.
---

# Secure Ward General — Chapter 8

Read `examples/ch08-security/README.md` and the README in the selected example folder
before running anything. They are the reader-facing source of truth and must
remain capability-equivalent to this skill.

## Scope and safety

The chapter has one primary guided, schema-changing example. RLS changes the
`wardgeneral` schema by creating a predicate function and security policy. It
does not create users or roles. The optional, non-schema-changing Azure SQL
Database auditing companion investigation is owned by the separate
`audit-wardgeneral` skill; do not run that workflow from this skill.

Do not turn conceptual chapter topics into additional workflows. Microsoft
Entra-only authentication, role design, TDE with customer-managed keys, Private
Link, classification, and Defender for SQL are discussion-only here.

Use the existing `examples/ch04-first-app/ch04.env` configuration. Never ask
for or place a SQL password on a command line. SQL entry points use the new
Go-based sqlcmd with `-G` Microsoft Entra authentication.

## RLS workflow

Every request to run the RLS app demo begins by running the read-only
`examples/ch08-security/rls/00-inspect-rls-state.ps1`. Existing Chapter 8 RLS
objects and generated `_local` files are normal installed state, not a reason
to reset. For the ordinary prompt `Run the Chapter 8 RLS app demo`, reuse that
state and start the secured runtimes. If generated DAB state is absent or
stale, `02-run-secured-dab.ps1` regenerates and validates it from the authored
Chapter 6 configuration.

Reset only when the reader explicitly asks for a clean-state reinstall or a
validation step proves the existing RLS objects have drifted or are broken. In
that case, run `examples/ch08-security/rls/00-reset-rls.ps1 -WhatIf`, show the
exact plan, and obtain explicit approval before dropping anything. The reset
must preserve every Chapter 4–6 object and must not stop an unrecognized
process.

After the reader approves the reset in chat, invoke
`00-reset-rls.ps1 -Confirm:$false`. The approval has already been obtained; do
not make the reader answer the same PowerShell confirmation in a terminal.

When the reader asks to run the RLS app demo or *Viewing as* example, including
the exact prompt "Run the Chapter 8 RLS app demo":

1. Assume the Chapter 2 Hyperscale database is deployed and the application
   from Chapters 4, 5, and 6 is built and deployed. Do not rerun their
   deployment or interview the reader for prerequisites.
2. If the inspection finds no RLS objects, run
   `examples/ch08-security/rls/01-setup-rls.ps1` to deploy and build the example.
   If the expected RLS objects already exist, skip setup and reuse them.
3. Start `examples/ch08-security/rls/02-run-secured-dab.ps1` with the terminal
   tool in asynchronous mode. This creates a visible, dedicated DAB terminal.
   Do not use `Start-Process`, a PowerShell job, redirected logs, or a hidden
   console. Run `probe-secured-mcp.ps1`; it waits up to 60 seconds for DAB to
   become ready and must return exactly seven authenticated tools. Do not run a
   separate early port probe.
4. Start `examples/ch08-security/rls/03-run-rls-app.ps1` with the terminal tool
   in asynchronous mode. This creates a second visible terminal, starts the app
   with `AiAssistance`, `AiAgent`, and `RowLevelSecurity` enabled, and opens the
   browser. It runs the same Azure sign-in, firewall, database, and MCP
   preflight as Chapters 4–6. Wait until HTTPS port 7170 is listening. Do not ask
   the reader to type either runtime command unless terminal tooling is
   unavailable.
5. Tell the reader that **Viewing as** intentionally lists many attending
   providers. They can compare **Admin — all patients** with any one or more
   attendings; do not ask them to report provider IDs back to the agent.
6. Have the reader observe that the board, patient charts, encounter search,
   and handoff candidates pivot to the selected provider while their SQL
   queries and stored procedures remain unchanged.
7. Explain both routes: `ChartRepository` stamps the scoped `AccessContext`
   directly, while the agent's HTTP handler sends the same identity as an
   EasyAuth-compatible principal; DAB authenticates it and forwards its claims
   into SQL `SESSION_CONTEXT`.
8. State that the local principal is simulated. In production, Entra/EasyAuth
   supplies authenticated claims; the model never chooses a provider ID.

`clinical.SaveShiftHandoff` retains the Chapter 6 system-provider attribution.
Chapter 8 restricts which encounter the acting provider can access; it does not
record that simulated provider as the handoff author.

State that the learning policy intentionally permits sessions with no context.
Do not describe that fail-open choice as production guidance. State that
historical similarity search and the named-replica Research page do not pivot
through this encounter policy because they do not read `clinical.Encounter`.

## Required report

Return the policy objects installed, app flag state, seven-tool secured DAB
readiness, and the reader-facing provider-filtering check.

## Files

| File | Role |
| --- | --- |
| `examples/ch08-security/README.md` | Chapter example map and scope boundary |
| `examples/ch08-security/prompts.md` | Canonical VS Code Chat skill prompts |
| `examples/ch08-security/rls/README.md` | Reader-facing RLS workflow |
| `examples/ch08-security/rls/00-inspect-rls-state.ps1` | Read-only Chapter 8 RLS state inspection |
| `examples/ch08-security/rls/00-reset-rls.ps1` | Guarded clean-state reset and verification |
| `examples/ch08-security/rls/00-reset-rls.sql` | Chapter 8 RLS object cleanup |
| `examples/ch08-security/rls/00-verify-clean.sql` | Clean-state assertion |
| `examples/ch08-security/rls/01-setup-rls.ps1` | Finite Chapter 8 setup, deploy, build, and DAB config validation |
| `examples/ch08-security/rls/02-run-secured-dab.ps1` | Visible foreground secured DAB runtime |
| `examples/ch08-security/rls/03-run-rls-app.ps1` | Visible foreground cumulative app runtime |
| `examples/ch08-security/rls/stop-local-apps.ps1` | Guarded app and DAB shutdown |
| `examples/ch08-security/rls/probe-secured-mcp.ps1` | Authenticated seven-tool probe |
| `examples/ch08-security/rls/new-client-principal.ps1` | Local EasyAuth principal-header builder |
| `examples/ch08-security/rls/enable-rls.ps1` | Configured passwordless RLS deployment entry point |
| `examples/ch08-security/rls/row-level-security.sql` | RLS predicate and security policy |
