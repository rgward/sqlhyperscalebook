# =============================================================================
# Azure SQL Hyperscale Unveiled — Chapter 9 (backups, restore, DR)
# pitr-restore.ps1
#
# NOTE ON LOCATION: this script still sits in examples/ch02-getting-started/
# because it was written during the Ch 2 dry-run deploy, but PITR moved out
# of Ch 2 in the 2026-06-29 rescope. It belongs to Ch 9 and moves there when
# that chapter is built.
#
# Point-in-time restore: take the wardgeneral database back to a moment 30
# minutes earlier into a brand-new database (PITR always restores into a
# NEW database — you cannot overwrite the source).
#
# What the reader should notice:
#   * PITR is snapshot-based on Hyperscale. The restore command returns
#     when the new database is ready; you don't wait for any data copy.
#   * The restored database is its own resource — its own SLO, its own
#     compute, its own billing. The source database is unaffected.
#   * Hyperscale PITR retention window: default 7 days; configurable up to
#     35 days. Cite Microsoft Learn — Hyperscale backups, access date
#     captured at write time.
#
# The *how it works* answer lives in Ch 3 (page servers + snapshots) and
# Ch 9 (HA/DR theory).
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
$MinutesAgo  = [int]($env:MINUTES_AGO ?? '30')
$RestoredDb  = $env:RESTORED_DB ?? "$Db-pitr-$((Get-Date).ToUniversalTime().ToString('HHmm'))"

# Compute the restore point (UTC ISO 8601). No GNU/BSD date divergence in
# PowerShell — DateTime math is native and cross-platform.
$PointInTime = (Get-Date).ToUniversalTime().AddMinutes(-$MinutesAgo).ToString('yyyy-MM-ddTHH:mm:ssZ')

Write-Host "--- PITR plan ---"
Write-Host "Source DB        : $Db on $Srv"
Write-Host "Target DB (new)  : $RestoredDb"
Write-Host "Point in time UTC: $PointInTime  ($MinutesAgo minutes ago)"

# Check the earliest restore point — handy if PITR retention is shorter
# than expected (e.g. recently created database).
Write-Host ""
Write-Host "--- Earliest restore point available ---"
az sql db show `
    --resource-group $Rg --server $Srv --name $Db `
    --query "{name:name, earliestRestoreDate:earliestRestoreDate}" `
    -o table

# ---------- The headline command --------------------------------------------
Write-Host ""
Write-Host "--- Restoring... ---"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
az sql db restore `
    --resource-group $Rg --server $Srv --name $Db `
    --dest-name $RestoredDb `
    --time $PointInTime `
    -o table
$sw.Stop()
Write-Host ("Restore wall clock: {0:N0}s" -f $sw.Elapsed.TotalSeconds)

# ---------- Inspect the new database ----------------------------------------
Write-Host ""
Write-Host "--- Restored DB summary ---"
az sql db show `
    --resource-group $Rg --server $Srv --name $RestoredDb `
    --query "{name:name, sku:currentServiceObjectiveName, status:status, edition:edition, source:sourceDatabaseId, restoreTime:restorePointInTime}" `
    -o table

@"

To connect:
  Server=tcp:$Srv.database.windows.net,1433;Database=$RestoredDb;Authentication=Active Directory Default;Encrypt=true;

To clean up the restored copy when you are done:
  az sql db delete --resource-group $Rg --server $Srv --name $RestoredDb --yes

Notes (Ch 2 §6):
  * PITR cannot overwrite the source — it always lands in a new database.
    To make the restored copy the live database, use database rename:
      az sql db rename ... (rename the source out of the way, then rename
      the restored DB into the source's slot)
  * The reverse-migration window (Hyperscale -> GP, 45 days, ONLY if the
    database was migrated into Hyperscale, NEVER if it was created as
    Hyperscale) is a different operation — see Ch 2 §1.
  * For cross-region restore, see geo-restore (Ch 9). For long-term retention,
    see LTR (Ch 9).
"@ | Write-Host
