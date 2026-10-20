# =============================================================================
# Azure SQL Hyperscale Unveiled — Chapter 2 §4 (Provision)
# add-replicas.ps1
#
# Add the optional named replica. The HA replica already exists — the deploy
# (provision-hyperscale.ps1) created the primary with one HA replica, which
# zone redundancy requires; this script leaves that count unchanged.
#
# HA and named replicas are different things: an HA replica is a failover
# target (and a read-scale endpoint via ApplicationIntent=ReadOnly); a named
# replica is a read-only scale-out object that looks like a separate
# database — never a failover target. The full HA-vs-named-vs-geo comparison
# lives in Ch 3 §7.
#
# Optional: it adds its own compute meter. Skip it and the rest of Chapter 2
# still works; run this script later when you reach Ch 3 §7 or Ch 5.
#
# Hard constraint to flag here (Ch 3 §8 introduces, Ch 10 §11 fills out):
# named replicas cannot live in a Hyperscale elastic pool.
#
# The replica created here is `wardgeneral-research`, and it is the one the
# rest of the book uses — Ch 3 §7 dissects it (sys.dm_hs_database_replicas
# proves it is genuinely its own database), and Ch 5 is where it first does
# real work: the app's Research page runs vector search on it, so the
# read-heavy corpus search never touches the OLTP primary. Ch 10 §8 covers
# scaling read-out further. Deploy it here so those chapters have it.
#
# It is created SERVERLESS (HS_S_Gen5_8) on purpose: a research endpoint is
# idle between queries, and serverless AUTOSCALES compute (1-8 vCores here)
# with per-second billing, so the replica drops to its floor when nobody is
# researching. Be precise about what serverless does NOT do on Hyperscale
# today: it does NOT auto-pause to zero. Auto-pause/auto-resume ships on
# General Purpose serverless now, and is on the roadmap for Hyperscale
# serverless -- so as of August 2026 the replica idles at its minimum vCore,
# billing continuously. Note the other trade too -- continuous priming is
# provisioned-only (Ch 9).
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
$NamedReplica    = $env:NAMED_REPLICA     ?? 'wardgeneral-research'   # read-only scale-out endpoint
$NamedReplicaSlo = $env:NAMED_REPLICA_SLO ?? 'HS_S_Gen5_8'            # serverless: autoscales to a 1-vCore floor when idle (auto-pause not on Hyperscale yet)

Write-Host "--- Before ---"
az sql db show `
    --resource-group $Rg --server $Srv --name $Db `
    --query "{name:name, sku:currentServiceObjectiveName, ha:highAvailabilityReplicaCount}" `
    -o table

# ---------- Add a named replica ---------------------------------------------
# Named replicas are created as a *new* database whose `createMode` is
# `Secondary` and whose source-database id points at the Hyperscale primary.
# `az sql db replica create` is the helper that wraps this; --secondary-type
# must be `Named` for a named replica (default `Geo`).
Write-Host ""
Write-Host "--- Named replica: $NamedReplica ---"
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

Notes (Ch 2 §4):
  * Two endpoints in play:
      Primary  ->  $Srv.database.windows.net  (database: $Db)
                   Read/write, plus reroute via ApplicationIntent=ReadOnly
                   to its HA replica:
                   Server=tcp:$Srv.database.windows.net,1433;Database=$Db;ApplicationIntent=ReadOnly;Authentication=Active Directory Default;Encrypt=true;
      Named    ->  $Srv.database.windows.net  (database: $NamedReplica)
                   Read-only. Looks like a separate database to clients.
                   NOT a failover target. Used by the app's Research page
                   from Ch 5 on.
  * Each replica is its own compute meter (per-replica billing) — Ch 2 §1
    pricing-model callout, in action. This one is serverless, so it bills
    per second on the compute it actually uses, dropping to its 1-vCore
    floor when idle. It does not pause: as of August 2026 auto-pause is a
    General Purpose feature, and is on the roadmap for Hyperscale.
  * Constraint to remember (planted here, expanded in Ch 10 §11): named
    replicas cannot live in a Hyperscale elastic pool.
"@ | Write-Host
