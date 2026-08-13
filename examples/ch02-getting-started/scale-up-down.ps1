# =============================================================================
# Azure SQL Hyperscale Unveiled — Chapter 10 §6 (scale strategy)
# scale-up-down.ps1
#
# NOTE ON LOCATION: this script still sits in examples/ch02-getting-started/
# because it was written during the Ch 2 dry-run deploy, but the topic moved
# out of Ch 2 in the 2026-06-29 rescope. It belongs to Ch 10 and moves there
# when that chapter is built.
#
# Feel the speed of Hyperscale scaling vs other Azure SQL tiers. One CLI
# command scales the primary compute up; another scales it back. Watch the
# database stay online throughout — storage is remote, so the operation is
# constant-time, NOT size-of-data.
#
# Two expectations to land:
#   1. The database stays online for the duration of the scale.
#   2. A brief connection drop happens at cutover when the failover
#      completes — apps need retry logic. (Serverless autoscale typically
#      does not drop connections; this is the provisioned-tier behaviour.)
#
# The *why-so-fast* answer is Ch 3 (page-server architecture). Scale
# strategy lives in Ch 10 §6.
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

$UpSlo   = $env:UP_SLO   ?? 'HS_Gen5_16'   # scale up:   8 vCore -> 16 vCore
$DownSlo = $env:DOWN_SLO ?? 'HS_Gen5_8'    # scale back: 16 vCore -> 8 vCore

function Get-UtcStamp { (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }

Write-Host "--- Before scale ---"
az sql db show `
    --resource-group $Rg --server $Srv --name $Db `
    --query "{name:name, sku:currentServiceObjectiveName, ha:highAvailabilityReplicaCount, state:status}" `
    -o table

# ---------- Scale up ---------------------------------------------------------
Write-Host ""
Write-Host "--- Scaling UP to $UpSlo ($(Get-UtcStamp)) ---"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
az sql db update `
    --resource-group $Rg --server $Srv --name $Db `
    --service-objective $UpSlo `
    -o table
$sw.Stop()
Write-Host ("Scale-up wall clock: {0:N0}s" -f $sw.Elapsed.TotalSeconds)

# Hyperscale scaling shows up as a service-tier-update operation. List it.
Write-Host ""
Write-Host "--- Recent scale operations ---"
az sql db op list `
    --resource-group $Rg --server $Srv --database $Db `
    --query "[?contains(operation,'Update') || contains(operation,'Scale')].{op:operation, state:state, start:startTime, end:lastModifyTime}" `
    -o table

# ---------- Scale back -------------------------------------------------------
Write-Host ""
Write-Host "--- Scaling DOWN to $DownSlo ($(Get-UtcStamp)) ---"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
az sql db update `
    --resource-group $Rg --server $Srv --name $Db `
    --service-objective $DownSlo `
    -o table
$sw.Stop()
Write-Host ("Scale-down wall clock: {0:N0}s" -f $sw.Elapsed.TotalSeconds)

Write-Host ""
Write-Host "--- After scale ---"
az sql db show `
    --resource-group $Rg --server $Srv --name $Db `
    --query "{name:name, sku:currentServiceObjectiveName, ha:highAvailabilityReplicaCount, state:status}" `
    -o table

@'

Notes (Ch 2 §4):
  * `az sql db update --service-objective` is the same command shape
    whether you are going up or down, and whether you are between any two
    Hyperscale SKUs (Gen5, Premium-series, M-series). The choice of SKU is
    where the difference lives, not the CLI.
  * The brief drop happens at cutover — the operation ends with a failover
    that resets connections and rolls back uncommitted transactions. Your
    app needs retry logic. Cite Microsoft Learn — Hyperscale FAQ.
  * On a non-Hyperscale tier, this same scale is a size-of-data copy: hours
    on a 1 TB database. The "Why Hyperscale matters" close in Ch 10 cashes
    in on that.
'@ | Write-Host
