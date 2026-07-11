---
name: verify-deployment
description: >-
  Verify an Azure SQL Hyperscale deployment from the CONTROL PLANE by
  summarizing the Azure Activity Log for the resource group — every operation
  Azure Resource Manager ran to build the database (create server, create
  database, firewall rules, Entra admin, threat-detection policy) — as
  events-by-status, events-by-operation, a most-recent-events table, and an
  explicit failure flag. Read-only; creates and changes nothing. USE WHEN the
  reader says any of: "verify my deployment", "check my deployment", "did my
  deployment succeed / work", "summarize the Azure Activity Log", "check the
  activity log", "confirm the deploy worked", "verify the deployment via the
  activity log", or "show me the control-plane activity for my database". This
  is the deploy / control-plane proof — the third verification angle alongside
  connect-and-verify.sql (engine/tier) and verify-data.sql (data). Scope:
  read-only Activity Log summary ONLY. Do NOT use to deploy, scale, connect, or
  run the schema/data checks — those are owned by the deploy-hyperscale skill
  and the connect-and-verify.sql / verify-data.sql scripts.
---

# Verify a Hyperscale deployment — control-plane proof

This skill answers "did my deployment actually succeed?" from the **Azure
control plane**, by summarizing the **Azure Activity Log** — the record of every
operation Azure Resource Manager performed to build the database. It runs one
**read-only** PowerShell script and interprets the result.

It is the **third verification angle** for the Ch 2 database:

- **Control plane (this skill)** — `verify-activity-log.ps1`: did ARM build it cleanly?
- **Engine / tier** — `connect-and-verify.sql`: is it SQL Server, is it Hyperscale?
- **Data** — `verify-data.sql`: did the schema + seed land?

## What to run

The script is **read-only** (just an `az monitor activity-log` query), so — unlike
connect-and-verify.sql and the schema scripts, which the reader drives — **you may
run this one yourself**.

```powershell
# Optional overrides (sensible defaults shown):
#   $env:RG='rg-collierhealth'   # resource group (default)
#   $env:OFFSET='6h'             # look-back window ##d##h; widen with '1d', '2d'
./examples/ch02-getting-started/verify-activity-log.ps1
```

If the reader asks to look further back (e.g. "over the last day"), set
`$env:OFFSET='1d'` before running.

## Preflight

- The script calls `az`, so the reader must be **signed in**: `az login` (and the
  right subscription, `az account set -s <subscription>`). The script prints a
  friendly "run `az login`" message if not.

## What the output means

The script prints three summaries — **events by status**, **events by operation**,
and a **most-recent-events** table — then a verdict:

- **Success:** every deploy operation shows `Succeeded` (with some transient
  `Started` / `Running` / `Accepted` states), and the script ends with
  **"No failed control-plane events — the deploy operations all succeeded."**
- **Failure:** the script lists any `Failed` / `Error` events (time, operation,
  resource) and tells the reader to investigate them before trusting the deploy.

Point out the useful details when they appear: **`Update SQL server firewall
rules`** (the client-IP rule), **`Update SQL database`** (the Hyperscale create),
and — a nice governance signal — **`auditIfNotExists` / `deployIfNotExists`
Policy actions** and **`Update server threat detection policy`**, which show
**Azure Policy** and **Microsoft Defender for SQL** acting on the new resources.

## Scope discipline

This skill **only** summarizes the Activity Log to verify a deployment. It does
**not** deploy, scale, add replicas, connect to the database, or run the
schema/data checks. If the reader wants any of those, hand off:

- Deploy a database → the **deploy-hyperscale** skill.
- Prove it's SQL Server / Hyperscale → `connect-and-verify.sql`.
- Prove the schema + seed → `verify-data.sql`.

## File this skill runs

| File | Role |
|---|---|
| `examples/ch02-getting-started/verify-activity-log.ps1` | read-only Azure Activity Log summary (control-plane deploy proof) |
