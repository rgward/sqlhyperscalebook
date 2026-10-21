#requires -Version 7.0
<#
.SYNOPSIS
    Warn, without failing, if wardgeneral still has a geo-secondary.

.DESCRIPTION
    Read-only. Lists the database's replication links and, for each geo link,
    prints the partner and its service objective. Chapter 9 creates its
    geo-secondary at the primary's size at that time (usually HS_Gen5_8); after
    Demo 1 scales the primary to HS_Gen5_40, a smaller geo-secondary may not
    keep up with Demo 2's write rate and can throttle the primary's log rate
    (RBIO_RG_GEOREPLICA waits). It also bills separately.

    Never throws: if the check itself can't run, it says so and returns.

.PARAMETER Server
    Logical server, short name or FQDN.
.PARAMETER Database
    Database name.
.PARAMETER ResourceGroup
    Defaults to $env:RG, then rg-collierhealth.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Server,
    [Parameter(Mandatory)] [string] $Database,
    [string] $ResourceGroup
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
if (-not $ResourceGroup) { $ResourceGroup = $env:RG ?? 'rg-collierhealth' }
$serverName = $Server -replace '\.database\.windows\.net$', ''

$raw = az sql db replica list-links --resource-group $ResourceGroup --server $serverName --name $Database --output json 2>$null
if ($LASTEXITCODE -ne 0 -or -not $raw) {
    Write-Host '  Geo-replica check: could not list replication links; skipped.' -ForegroundColor DarkGray
    return
}

$links = @($raw | Out-String | ConvertFrom-Json)
$geoLinks = @($links | Where-Object {
    $linkType = $_.PSObject.Properties['linkType']
    if ($linkType -and $linkType.Value) { $linkType.Value -eq 'GEO' } else { $_.partnerServer -ne $serverName }
})

if ($geoLinks.Count -eq 0) {
    Write-Host '  Geo-replica check: no geo-secondary on this database.' -ForegroundColor DarkGray
    return
}

foreach ($link in $geoLinks) {
    $partnerSlo = az sql db show --resource-group $ResourceGroup --server $link.partnerServer --name $link.partnerDatabase `
        --query currentServiceObjectiveName --output tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $partnerSlo) { $partnerSlo = 'unknown' }

    Write-Host ''
    Write-Host ("  WARNING: a geo-secondary ({0}/{1}, {2}, {3}) is replicating this database." -f
        $link.partnerServer, $link.partnerDatabase, $link.partnerLocation, $partnerSlo) -ForegroundColor Yellow
    Write-Host '  It bills separately, and if it is smaller than the primary during Demo 2 it can' -ForegroundColor Yellow
    Write-Host '  throttle the primary''s log rate (RBIO_RG_GEOREPLICA waits), so your results may' -ForegroundColor Yellow
    Write-Host '  differ from the book. If you no longer need it, remove it with Chapter 9''s' -ForegroundColor Yellow
    Write-Host '  examples/ch09-ha-resiliency/geo/cleanup-geo-replica.ps1. Continuing.' -ForegroundColor Yellow
}
