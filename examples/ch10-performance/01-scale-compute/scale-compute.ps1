<#
.SYNOPSIS
    Previews and optionally performs the stage 1 Standard-series compute scale.

.EXAMPLE
    ./scale-compute.ps1 -TargetServiceObjective HS_Gen5_16
    ./scale-compute.ps1 -TargetServiceObjective HS_Gen5_16 -Approve
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^HS_Gen5_[0-9]+$')]
    [string] $TargetServiceObjective,

    [string] $ResourceGroup,

    [switch] $Approve
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$loadEnv = Join-Path $PSScriptRoot '..\..\ch04-first-app\load-env.ps1'
. $loadEnv -Require @('WardGeneral__Server', 'WardGeneral__Database') -Quiet
if (-not $ResourceGroup) { $ResourceGroup = $env:RG ?? 'rg-collierhealth' }

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI was not found. Install it, run az login, and retry.'
}

$serverFqdn = $env:WardGeneral__Server
$serverName = $serverFqdn.Split('.')[0]
$database = $env:WardGeneral__Database

$current = az sql db show `
    --resource-group $ResourceGroup `
    --server $serverName `
    --name $database `
    --query '{name:name,status:status,edition:edition,serviceObjective:currentServiceObjectiveName,capacity:currentSku.capacity,family:currentSku.family}' `
    --output json | ConvertFrom-Json

Write-Host 'Chapter 10 stage 1 compute-scale preview' -ForegroundColor Cyan
Write-Host ("  Database   {0} @ {1}" -f $database, $serverName)
Write-Host ("  Status     {0}" -f $current.status)
Write-Host ("  Current    {0}" -f $current.serviceObjective)
Write-Host ("  Requested  {0}" -f $TargetServiceObjective)

if ($current.edition -ne 'Hyperscale') {
    throw "Expected a Hyperscale database; Azure reports edition '$($current.edition)'."
}
if ($current.serviceObjective -eq $TargetServiceObjective) {
    Write-Host 'The database is already at the requested service objective.' -ForegroundColor Green
    return
}
if ($current.serviceObjective -like 'HS_S_*') {
    Write-Host ''
    Write-Host ("  This changes the compute model from serverless ({0}) to provisioned ({1})." -f
        $current.serviceObjective, $TargetServiceObjective) -ForegroundColor Yellow
    Write-Host '  Provisioned compute bills for every vCore every hour, whether or not the database is busy.' -ForegroundColor Yellow
}
if (-not $Approve) {
    Write-Host ''
    Write-Host 'Preview only. This command changes a billable Azure resource.' -ForegroundColor Yellow
    Write-Host ("Re-run with -Approve to scale to {0}." -f $TargetServiceObjective) -ForegroundColor Yellow
    return
}

$startedAt = Get-Date
az sql db update `
    --resource-group $ResourceGroup `
    --server $serverName `
    --name $database `
    --edition Hyperscale `
    --service-objective $TargetServiceObjective `
    --output none
$elapsed = (Get-Date) - $startedAt

$updated = az sql db show `
    --resource-group $ResourceGroup `
    --server $serverName `
    --name $database `
    --query '{status:status,serviceObjective:currentServiceObjectiveName}' `
    --output json | ConvertFrom-Json

Write-Host ("Scale complete in {0:N0} seconds." -f $elapsed.TotalSeconds) -ForegroundColor Green
Write-Host ("  Status     {0}" -f $updated.status)
Write-Host ("  Current    {0}" -f $updated.serviceObjective)
