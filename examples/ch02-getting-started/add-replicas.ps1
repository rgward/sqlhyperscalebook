# =============================================================================
# Azure SQL Hyperscale Unveiled — Chapter 2 §5
# add-replicas.ps1
#
# Add a second HA replica, then add a named replica. Show that they are
# different things: HA replicas are failover targets (and read-scale
# endpoints via ApplicationIntent=ReadOnly); named replicas are read-only
# scale-out objects that look like separate databases — never failover
# targets.
#
# Two realities the chapter wants to land (§5):
#   1. First-failover RTO depends on whether you pre-provisioned an HA
#      replica. With 0 HA replicas, the system must build one from scratch
#      on failover (slower). With >=1, the spare is hot. Forward-point Ch 9.
#   2. Named replicas are NOT failover targets. The full HA-vs-named-vs-geo
#      comparison lives in Ch 3 §7.
#
# Hard constraint to flag here (Ch 3 §8 introduces, Ch 10 §11 fills out):
# named replicas cannot live in a Hyperscale elastic pool.
#
# Repo convention: PowerShell for every script, `az` CLI for Azure
# control-plane calls. Run in PowerShell 7+ (pwsh).
# =============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$Rg  = $env:RG  ?? 'rg-collierhealth'
if (-not $env:SRV) { throw 'Set SRV to the logical server name (collierhealth-...).' }
$Srv = $env:SRV
$Db  = $env:DB  ?? 'wardgeneral'
$NamedReplica    = $env:NAMED_REPLICA     ?? 'wardgeneral-nr1'   # read-only scale-out endpoint
$NamedReplicaSlo = $env:NAMED_REPLICA_SLO ?? 'HS_Gen5_4'

Write-Host "--- Before ---"
az sql db show `
    --resource-group $Rg --server $Srv --name $Db `
    --query "{name:name, sku:currentServiceObjectiveName, ha:highAvailabilityReplicaCount}" `
    -o table

# ---------- 1. Add a second HA replica --------------------------------------
# HA replicas live "inside" the primary database object — there is no
# separate database resource. Increment the count.
Write-Host ""
Write-Host "--- 1/2 HA replica: increment to 2 ---"
az sql db update `
    --resource-group $Rg --server $Srv --name $Db `
    --ha-replicas 2 `
    -o table

Write-Host ""
Write-Host "Tip: connect with ApplicationIntent=ReadOnly to be routed to an HA replica."
Write-Host "Connection-string fragment:"
Write-Host "  Server=tcp:$Srv.database.windows.net,1433;Database=$Db;ApplicationIntent=ReadOnly;Authentication=Active Directory Default;Encrypt=true;"

# ---------- 2. Add a named replica ------------------------------------------
# Named replicas are created as a *new* database whose `createMode` is
# `Secondary` and whose source-database id points at the Hyperscale primary.
# `az sql db replica create` is the helper that wraps this; --secondary-type
# must be `Named` for a named replica (default `Geo`).
Write-Host ""
Write-Host "--- 2/2 Named replica: $NamedReplica ---"
az sql db replica create `
    --resource-group $Rg --server $Srv --name $Db `
    --partner-server $Srv --partner-database $NamedReplica `
    --secondary-type Named `
    --service-objective $NamedReplicaSlo `
    -o table

# ---------- Show what we have ----------------------------------------------
Write-Host ""
Write-Host "--- Replica list ---"
az sql db replica list-links `
    --resource-group $Rg --server $Srv --name $Db `
    -o table

Write-Host ""
Write-Host "--- Named replica details ---"
az sql db show `
    --resource-group $Rg --server $Srv --name $NamedReplica `
    --query "{name:name, sku:currentServiceObjectiveName, ha:highAvailabilityReplicaCount, state:status, secondaryType:secondaryType}" `
    -o table

@"

Notes (Ch 2 §5):
  * Two endpoints in play:
      Primary  ->  $Srv.database.windows.net  (database: $Db)
                   Read/write, plus reroute via ApplicationIntent=ReadOnly
                   to an HA replica.
      Named    ->  $Srv.database.windows.net  (database: $NamedReplica)
                   Read-only. Looks like a separate database to clients.
                   NOT a failover target.
  * Each replica is its own compute meter (per-replica billing) — Ch 2 §1
    pricing-model callout, in action.
  * Constraint to remember (planted here, expanded in Ch 10 §11): named
    replicas cannot live in a Hyperscale elastic pool.
"@ | Write-Host
