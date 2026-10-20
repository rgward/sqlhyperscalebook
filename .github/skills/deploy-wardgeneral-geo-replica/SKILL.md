---
name: deploy-wardgeneral-geo-replica
description: >-
  Create, verify, and clean up the Chapter 9 Ward General Hyperscale
  geo-replica: read the source from ch04.env, preview and explicitly approve
   creation of a reader-named Entra-only logical server in the source region's
   Azure paired region (or a reader-chosen other region) with the
   signed-in user as Entra admin, create the wardgeneral
  geo-secondary, verify both replication links, and perform guarded cleanup.
  USE WHEN the reader says "create the Ward General geo-replica", "deploy geo
   replication", "run the Chapter 9 geo example",
   "geo-replicate my CMK database", "fix geo-replication TDE permissions",
   "verify the geo-secondary", or "clean up the geo-replica". Do not create a
   failover group or fail over the database.
---

# Deploy the Ward General geo-replica — Chapter 9

Read `examples/ch09-ha-resiliency/README.md` and
`examples/ch09-ha-resiliency/geo/README.md` before running anything. They are
the reader-facing source of truth and must remain capability-equivalent to this
skill.

## Scope and safety

This workflow creates a billable logical server and Hyperscale geo-secondary.
It uses standalone active geo-replication and does not perform failover.

- Use `examples/ch04-first-app/ch04.env` for the source server and database.
- Use the active Azure CLI subscription and the resource group from `RG`
  (`ch04.env` or shell), defaulting to `rg-collierhealth`.
- The signed-in Azure CLI user is the target server's Microsoft Entra admin.
- Never pass `-Execute` before showing the preview and obtaining explicit
  approval for the exact subscription, source, and target.
- Require one globally unique target server name and use it unchanged through
   deployment, verification, and cleanup.
- The target region defaults to the Azure paired region of the source's region
  (Central US ↔ East US 2). Pass `-TargetLocation` only if the reader names a
  region. Never place the target in the source's own region — the script
  refuses, because a same-region geo-secondary gives no regional protection.
- Never modify or delete the source server or source `wardgeneral` database.
- Detect the source server-level TDE protector. Do not enable CMK when the
   source uses the default service-managed protector, and never replace, rotate,
   or remove a source CMK.
- Create the target with zero HA replicas and zone redundancy disabled. Do not
   claim that this lower-cost topology matches the source's local availability.
- Do not create a failover group and do not initiate planned or forced
  geo-failover.

## Workflow

1. Ask for a globally unique Azure SQL logical server name, then run
   `examples/ch09-ha-resiliency/geo/deploy-geo-replica.ps1 -TargetServer
   <name>` without `-Execute`.
2. Report the subscription, resource group, source database and region, target
   server and region (and whether it is the default paired region or
   reader-specified), signed-in Entra administrator, service objective, HA
   replica counts, zone-redundancy settings, backup redundancy, and source TDE
   protector. Explain that the target deliberately uses zero HA replicas and
   no zone redundancy: cross-region DR remains, but local target recovery can
   take longer because no hot HA standby exists.
3. Explain that the target server is created with its system-assigned identity
   and Entra-only administrator in the same server-create operation. The portal
   geo-replica blade does not provide that server-identity prerequisite.
4. If the source protector is `ServiceManaged`, report that no Key Vault work
   is required. If it is `AzureKeyVault`, report the existing protector key and
   Key Vault authorization model. Explain that execution grants the target
   identity `Get`, `WrapKey`, and `UnwrapKey` through either the vault access
   policy or the **Key Vault Crypto Service Encryption User** role, then
   registers that key on the target. These actions do not change the source
   protector.
5. Obtain explicit approval for both billable resources and, for a CMK source,
   the target Key Vault access and key registration.
6. Run the same command once with `-Execute`. Do not automatically retry a
   failed create operation.
7. Report `TargetServerCreated`, `TargetServerPrincipalId`,
   `TargetCmkAccessConfigured`, `TargetProtectorKeyRegistered`, and
   `GeoReplicaSubmitted` when applicable. Submission does not prove completion.
8. After Azure reports the secondary online, run
   `verify-geo-replica.ps1 -TargetServer <name>`. Require
   `GeoReplicaVerification=PASS` and report the source, target identity,
   geo-secondary properties, and link states.
9. Leave the resources deployed until the reader asks for cleanup.
10. For cleanup, run `cleanup-geo-replica.ps1 -TargetServer <name>` without
   `-Execute`. Show the exact retained source, replication link, secondary,
   target server, ownership tags, and database inventory. Do not continue if
   the script reports unexpected databases.
11. Obtain explicit cleanup approval, then rerun with `-Execute`. Require both
    `GeoReplicationLinkRemoved` and `TargetServerDeleted`.

## Required report

Distinguish preview, accepted creation, online resource state, verified
replication, and cleanup. State that active geo-replication is asynchronous to
primary commit and that the secondary remains read-only until promoted.

## Files

| File | Role |
| --- | --- |
| `examples/ch09-ha-resiliency/geo/README.md` | Reader runbook and safety boundary |
| `examples/ch09-ha-resiliency/geo/deploy-geo-replica.ps1` | Preview-first target-server and geo-secondary deployment |
| `examples/ch09-ha-resiliency/geo/verify-geo-replica.ps1` | Read-only resource and replication-link verification |
| `examples/ch09-ha-resiliency/geo/cleanup-geo-replica.ps1` | Guarded replication-link and target-server cleanup |