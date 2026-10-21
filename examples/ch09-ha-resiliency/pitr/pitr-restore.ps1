# =============================================================================
# Azure SQL Hyperscale Unveiled — Chapter 9 (backups, restore, DR)
# pitr-restore.ps1
#
# NOTE ON LOCATION: written during the Ch 2 dry-run deploy and parked in
# examples/ch02-getting-started/ until 2026-08-13, when it moved to Chapter 9.
# PITR left Ch 2 in the 2026-06-29 rescope; Ch 9 owns it.
#
# Point-in-time restore: capture a current-as-of-start copy of wardgeneral in a
# brand-new database (PITR always restores into a NEW database — you cannot
# overwrite the source). Preview-only unless -Execute is supplied.
#
# What the reader should notice:
#   * PITR is snapshot-based on Hyperscale. The restore is submitted
#     asynchronously so sys.dm_operation_status can show its progress.
#   * The restored database is a low-compute serverless test copy, not a
#     reproduction of the source's production compute and replica topology.
#     Hyperscale serverless autoscales; auto-pause is a Hyperscale preview this
#     script doesn't configure, so don't count on the copy pausing.
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

#requires -Version 7.0
[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [DateTimeOffset] $RestorePointUtc,
  [string] $ResourceGroup,
  [string] $Server,
  [string] $Database,
  [string] $RestoredDatabase = 'wardgeneral-pitr-demo',
  [string] $TargetServiceObjective = 'HS_S_Gen5_8',
  [double] $TargetMinVCore = 1,
  [switch] $Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$loadEnv = Join-Path $PSScriptRoot '..' '..' 'ch04-first-app' 'load-env.ps1'
if (Test-Path $loadEnv) { & $loadEnv -Optional -Quiet }
if (-not $ResourceGroup) { $ResourceGroup = $env:RG ?? 'rg-collierhealth' }

if (-not $Server) { $Server = $env:WardGeneral__Server }
if (-not $Database) { $Database = $env:WardGeneral__Database ?? 'wardgeneral' }
if ([string]::IsNullOrWhiteSpace($Server) -or $Server -match '<[^>]*>') {
  throw 'No server. Fill in WardGeneral__Server in examples/ch04-first-app/ch04.env, set the environment variable, or pass -Server explicitly.'
}

$logicalServer = $Server -replace '\.database\.windows\.net$', ''
if ($RestoredDatabase -notmatch '^wardgeneral-pitr-') {
  throw "Restore target '$RestoredDatabase' is outside this demo. Chapter 9 restored database names must start with 'wardgeneral-pitr-'."
}
if ($TargetServiceObjective -notmatch '^HS_S_') {
  throw "Target service objective '$TargetServiceObjective' is outside this demo. Use a Hyperscale serverless objective such as 'HS_S_Gen5_8'."
}
if ($TargetMinVCore -le 0) {
  throw 'TargetMinVCore must be greater than zero.'
}
$pointInTime = $RestorePointUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')

Write-Host "--- PITR plan ---"
Write-Host "Source DB        : $Database on $logicalServer"
Write-Host "Target DB (new)  : $RestoredDatabase"
Write-Host "Point in time UTC: $pointInTime"
Write-Host "Target compute   : $TargetServiceObjective (serverless, minimum $TargetMinVCore vCore)"
Write-Host "Target topology  : No requested HA replicas or named replicas"

# Check the earliest restore point — handy if PITR retention is shorter
# than expected (e.g. recently created database).
Write-Host ""
Write-Host "--- Earliest restore point available ---"
az sql db show `
  --resource-group $ResourceGroup --server $logicalServer --name $Database `
    --query "{name:name, earliestRestoreDate:earliestRestoreDate}" `
    -o table

$existingTarget = az sql db list `
  --resource-group $ResourceGroup `
  --server $logicalServer `
  --query "[?name=='$RestoredDatabase'].name | [0]" `
  --output tsv
if ($existingTarget) {
  throw "Target database '$RestoredDatabase' already exists, for example a test copy kept from an earlier run. Remove it with cleanup-pitr.ps1, or pass a different -RestoredDatabase that starts with 'wardgeneral-pitr-'."
}

if (-not $Execute) {
  Write-Host ''
  Write-Host 'PREVIEW ONLY. This restore creates a billable database. Rerun with -Execute after approval.' -ForegroundColor Yellow
  return
}

# ---------- Submit the restore ----------------------------------------------
Write-Host ""
Write-Host "--- Submitting restore... ---"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
az sql db restore `
  --resource-group $ResourceGroup --server $logicalServer --name $Database `
  --dest-name $RestoredDatabase `
  --time $pointInTime `
  --service-objective $TargetServiceObjective `
  --min-capacity $TargetMinVCore `
  --no-wait `
    --output none
$sw.Stop()
Write-Host ("RestoreSubmitted={0}" -f $RestoredDatabase)
Write-Host ("SubmissionDurationSeconds={0:N0}" -f $sw.Elapsed.TotalSeconds)

@"

To inspect restore progress:
  ./show-operation-status.ps1 -RestoredDatabase '$RestoredDatabase'

That command polls the management operation until it completes or reaches its
bounded timeout. Continue to verification only after it reports COMPLETED.

To connect:
  Server=tcp:$logicalServer.database.windows.net,1433;Database=$RestoredDatabase;Authentication=Active Directory Default;Encrypt=true;

To clean up the restored copy when you are done testing (previews first; add
-Execute after reviewing):
  ./cleanup-pitr.ps1 -RestoredDatabase '$RestoredDatabase'

Notes (Ch 9):
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
