---
name: recover-wardgeneral-pitr
description: >-
   Run the Chapter 9 Ward General PITR test-copy demonstration: capture the
   source database's current server UTC time, preview and explicitly approve a
   lower-compute Hyperscale serverless point-in-time restore, validate the
   restored Ward General database without using the app, leave it for testing,
   and perform guarded cleanup on a separate request. USE WHEN the reader says "Create a current Ward General test
   database using PITR" (the book's prompt), "run the Chapter 9 PITR demo", "create a
   PITR test copy", "create a current Ward General test database", "test Ward
   General restore", or "clean up the Chapter 9 restored database". Do not
   alter source data or overwrite the source database.
---

# Recover Ward General with PITR — Chapter 9

Read `examples/ch09-ha-resiliency/README.md` and
`examples/ch09-ha-resiliency/pitr/README.md` before running anything. They are
the reader-facing source of truth and must remain capability-equivalent to this
skill.

## Scope and safety

The preparation step reads `SYSUTCDATETIME()` from the source. PITR creates a
separate billable Hyperscale serverless test database. It never overwrites
`wardgeneral`.

- Preserve one `RestorePointUtc` throughout the run.
- Never substitute client time or a relative minutes-ago estimate.
- Preview restore and cleanup before requesting explicit approval.
- Never automatically retry a restore whose point is not yet available.
- Never delete a database whose name does not begin `wardgeneral-pitr-`.
- Never modify source data.

## Workflow

### Prepare

1. Run `examples/ch09-ha-resiliency/pitr/prepare-pitr.ps1`.
2. Require exactly one `RestorePointUtc`. Preserve the raw output. Explain
   that this is a current-as-of-start test copy, not a continuously current
   clone.

### Restore

3. Use the default target `wardgeneral-pitr-demo` (the name the book shows)
   unless the reader asks for another name beginning with `wardgeneral-pitr-`.
   Run `pitr-restore.ps1 -RestorePointUtc <value>` without `-Execute`. If the
   target already exists from an earlier run, stop and offer the guarded
   cleanup or a different name; never delete it as part of the restore.
4. Explain that the operation creates a billable `HS_S_Gen5_8` Hyperscale
   serverless test database with a 1-vCore minimum. Show the source, target,
   earliest restore point, exact selected point, and target compute. State that
   Hyperscale serverless autoscales but does not auto-pause, and that this test
   copy intentionally does not reproduce the source's compute or replica
   topology.
5. Obtain explicit approval, then rerun the identical command with `-Execute`.
   It submits the restore asynchronously with `--no-wait`; do not treat command
   return as restore completion.
6. If Azure says the point is too recent, stop. Preserve the same timestamp
   and instruct the reader to rerun that exact restore later. Do not substitute
   a relative minutes-ago estimate or poll.

### Observe and verify

7. Run `show-operation-status.ps1 -RestoredDatabase <name>` within
   approximately one hour of the restore. It connects to `master`, where the
   server-level principal can read `sys.dm_operation_status`. The script polls
   every 15 seconds for at most 60 minutes and exits on `COMPLETED`, `FAILED`,
   `CANCELLED`, or timeout. Run it in a foreground synchronous terminal with no
   client timeout shorter than 65 minutes; do not use an execution helper that
   detaches the command after a shorter limit. Do not end the workflow or rely
   on the reader to report terminal completion. Report the operation, state,
   percentage, errors, start time, last-modified time, and completed duration.
   Continue only when it emits `RestoreOperation=COMPLETED`. Treat this as
   management-operation evidence, not data-recovery proof.
8. Run `verify-pitr.ps1 -RestoredDatabase <name>`. Require
   `PitrVerification=PASS`. This validates the restored Azure resource and
   runs Chapter 2's Ward General schema, volume, and coherence checks directly
   against the restored database; it does not start or repoint the app. Azure
   can return a null `sourceDatabaseId` after PITR completes, so use the
   completed restore-operation row plus these data checks as the recovery
   evidence; reject a conflicting source ID if Azure does return one.
9. Stop here and give the required report. As the book does, leave the
   restored database in place so the reader can connect to it with SSMS or
   VS Code and test it. Remind them that it is billable while it exists
   (serverless does not auto-pause) and that cleanup is a separate request.

### Clean up (only when the reader asks)

Run this section only when the reader asks to clean up, for example "clean up
the Chapter 9 restored database". Do not chain it to the restore.

10. Run `cleanup-pitr.ps1 -RestoredDatabase <name>` without `-Execute`. Show
    the exact restored resource.
11. Obtain explicit approval because cleanup deletes the restored database.
12. Rerun cleanup with `-Execute`. Require `Deleted=<name>`.

## Required report

Report the source and target names, exact restore point, earliest
available restore point, requested and resulting serverless configuration,
submission duration, completed restore duration, operation-status row, and Ward
General verification result. State that the restored database is still
running and billable, and give the cleanup prompt. When cleanup runs later,
report its result.
Distinguish a locally validated script from a completed live Azure recovery.

## Files

| File | Role |
| --- | --- |
| `examples/ch09-ha-resiliency/pitr/README.md` | Reader runbook and command sequence |
| `examples/ch09-ha-resiliency/pitr/prepare-pitr.ps1` | Passwordless SQL preparation driver |
| `examples/ch09-ha-resiliency/pitr/prepare-recovery-point.sql` | Read-only source UTC restore-point capture |
| `examples/ch09-ha-resiliency/pitr/pitr-restore.ps1` | Preview-first Azure CLI restore |
| `examples/ch09-ha-resiliency/pitr/show-operation-status.ps1` | Passwordless `master` query driver for recent operation status |
| `examples/ch09-ha-resiliency/pitr/operation-status.sql` | `sys.dm_operation_status` restore evidence |
| `examples/ch09-ha-resiliency/pitr/verify-pitr.ps1` | Source/restored verification driver |
| `examples/ch09-ha-resiliency/pitr/cleanup-pitr.ps1` | Guarded restored-database cleanup |
