<#
.SYNOPSIS
    Read-only. Reports what your ch05.env names, what already exists in Azure,
    and what deploy-ai.ps1 would therefore create.

.DESCRIPTION
    Run this before deploy-ai.ps1. It answers the question a reader actually
    has -- "am I about to build something I did not mean to build?" -- while
    that is still a cheap question to ask.

    It reads ch05.env, then probes each resource by name with `az ... show`.
    That includes the Chapter 2 database (required) and the optional
    wardgeneral-research named replica the Research page reads.
    Every call is a GET. This script creates nothing, changes nothing, deletes
    nothing, and needs no more permission than the ability to read the
    resources it names.

    WHAT IT IS GOOD AT. Catching a typo. A misspelled AI_RESOURCE reads as "does
    not exist, will be created", which is the honest answer and also the warning
    -- a name you expected to already exist showing up as "will create" means
    you typed it wrong, or you are pointed at the wrong subscription.

    It also catches the one case in this chapter where a re-run against a
    working environment still creates something: a Content Safety resource whose
    name is not the derived <AI_RESOURCE>-contentsafety.

    WHAT IT IS NOT. It is not a permission check and not a health check. A
    resource can exist and still be misconfigured. It reports existence and
    names, nothing deeper.

.PARAMETER NoGateway
    Check as if you intend to run deploy-ai.ps1 -NoGateway: skip APIM, content
    safety and the publisher email.

.PARAMETER Path
    The env file to read. Defaults to ch05.env beside this script.

.EXAMPLE
    ./check-ai-env.ps1

.EXAMPLE
    ./check-ai-env.ps1 -NoGateway
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [switch] $NoGateway,
    [string] $Path
)

$ErrorActionPreference = 'Stop'

# Required set depends on whether the gateway is in play: PUBLISHER_EMAIL is
# APIM's contact and is meaningless without it.
$require = @('RG', 'SRV', 'AI_RESOURCE', 'WardGeneral__Server', 'WardGeneral__Database')
if (-not $NoGateway) { $require += 'PUBLISHER_EMAIL' }

$loader = Join-Path $PSScriptRoot 'load-env.ps1'
& $loader -Path $Path -Require $require -Quiet

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI (az) not found. Install it, then run az login.'
}

# The parameter is AzArgs, not Args: $Args is an automatic variable, and
# shadowing it inside a function is the kind of thing that parses cleanly and
# misbehaves.
function Get-AzValue([string[]] $AzArgs) {
    $v = (& az @AzArgs 2>$null | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($v)) { return $null }
    return $v
}

$rg      = $env:RG
$srv     = $env:SRV
$ai      = $env:AI_RESOURCE
$apim    = if ([string]::IsNullOrWhiteSpace($env:APIM_NAME)) { "$ai-gateway" }        else { $env:APIM_NAME }
$csDeriv = "$ai-contentsafety"
$cs      = if ([string]::IsNullOrWhiteSpace($env:CS_RESOURCE)) { $csDeriv }           else { $env:CS_RESOURCE }

if (-not [string]::IsNullOrWhiteSpace($env:SUBSCRIPTION_ID)) {
    az account set --subscription $env:SUBSCRIPTION_ID --output none 2>$null
}

$acct = Get-AzValue @('account', 'show', '--query', '{n:name, u:user.name}', '-o', 'tsv')
if (-not $acct) { throw 'Not signed in. Run: az login' }

Write-Host ''
Write-Host 'Chapter 5 environment check (read-only)' -ForegroundColor Cyan
Write-Host "  subscription : $acct" -ForegroundColor DarkGray
Write-Host ''

$rows    = [System.Collections.Generic.List[object]]::new()
$notes   = [System.Collections.Generic.List[string]]::new()
$creates = 0

function Add-Row([string] $What, [string] $Name, [bool] $Exists, [string] $WhenAbsent) {
    $status = if ($Exists) { 'exists' } else { $WhenAbsent }
    $script:rows.Add([pscustomobject]@{ Resource = $What; Name = $Name; Status = $status })
    if (-not $Exists -and $WhenAbsent -eq 'WILL BE CREATED') { $script:creates++ }
}

# -- Chapter 2's resources. Prerequisites, never created by this chapter.
$rgOk = [bool] (Get-AzValue @('group', 'show', '-n', $rg, '--query', 'name', '-o', 'tsv'))
Add-Row 'Resource group' $rg $rgOk 'MISSING - prerequisite'

$srvOk = [bool] (Get-AzValue @('sql', 'server', 'show', '-n', $srv, '-g', $rg, '--query', 'name', '-o', 'tsv'))
Add-Row 'SQL server' $srv $srvOk 'MISSING - prerequisite'

if ($srvOk) {
    $mi = Get-AzValue @('sql', 'server', 'show', '-n', $srv, '-g', $rg, '--query', 'identity.principalId', '-o', 'tsv')
    Add-Row 'Server managed identity' $(if ($mi) { $mi } else { '(none yet)' }) ([bool]$mi) 'WILL BE CREATED'
}

# -- The Chapter 2 database and its optional named replica. Read-only: this
# chapter creates neither. The database is required for everything here; the
# named replica only for the Research page, and Chapter 2 makes it optional.
$db      = $env:WardGeneral__Database
$replica = 'wardgeneral-research'
$dbOk      = $false
$replicaOk = $false
if ($srvOk) {
    $dbOk      = [bool] (Get-AzValue @('sql', 'db', 'show', '-n', $db,      '-s', $srv, '-g', $rg, '--query', 'name', '-o', 'tsv'))
    $replicaOk = [bool] (Get-AzValue @('sql', 'db', 'show', '-n', $replica, '-s', $srv, '-g', $rg, '--query', 'name', '-o', 'tsv'))
}
Add-Row 'Database' $db $dbOk 'MISSING - prerequisite'
Add-Row 'Named replica' $replica $replicaOk 'MISSING - optional (Research page)'
if ($srvOk -and -not $replicaOk) {
    $notes.Add("The Research page reads the '$replica' named replica, which Chapter 2 makes optional. Create it with examples/ch02-getting-started/add-replicas.ps1 (billable, serverless) before using Research. The AI assistance card works without it.")
}

# -- The AI resources.
$aiOk = [bool] (Get-AzValue @('cognitiveservices', 'account', 'show', '-n', $ai, '-g', $rg, '--query', 'name', '-o', 'tsv'))
Add-Row 'Foundry account' $ai $aiOk 'WILL BE CREATED'

if ($aiOk) {
    $deps = Get-AzValue @('cognitiveservices', 'account', 'deployment', 'list', '-n', $ai, '-g', $rg, '--query', '[].name', '-o', 'tsv')
    $have = if ($deps) { $deps -split '\r?\n' } else { @() }
    foreach ($model in @('text-embedding-3-large', 'gpt-5')) {
        Add-Row 'Model deployment' $model ($have -contains $model) 'WILL BE CREATED'
    }
} else {
    Add-Row 'Model deployment' 'text-embedding-3-large' $false 'WILL BE CREATED'
    Add-Row 'Model deployment' 'gpt-5'                  $false 'WILL BE CREATED'
}

if (-not $NoGateway) {
    $apimOk = [bool] (Get-AzValue @('apim', 'show', '-n', $apim, '-g', $rg, '--query', 'name', '-o', 'tsv'))
    Add-Row 'APIM gateway' $apim $apimOk 'WILL BE CREATED'
    if (-not $apimOk) {
        $notes.Add('APIM StandardV2 takes 30-45 minutes to provision and is billable while it exists. -NoGateway skips it.')
    }

    $csOk = [bool] (Get-AzValue @('cognitiveservices', 'account', 'show', '-n', $cs, '-g', $rg, '--query', 'name', '-o', 'tsv'))
    Add-Row 'Content Safety' $cs $csOk 'WILL BE CREATED'

    # The one value in this chapter that changes behaviour rather than naming -
    # but only worth a note when something is actually about to be created. A
    # resource that already exists needs no comment: the row above says so, and
    # CS_RESOURCE being a non-derived name is the entry working, not a problem.
    # Say nothing then, or the reader goes hunting for an action that isn't there.
    if (-not $csOk) {
        $existingCs = Get-AzValue @('cognitiveservices', 'account', 'list', '-g', $rg, '--query', "[?kind=='ContentSafety'].name", '-o', 'tsv')
        if ($existingCs) {
            $notes.Add("No Content Safety resource named '$cs', but this group already has: $($existingCs -replace '\r?\n', ', '). If you meant to reuse one, put its name in CS_RESOURCE - otherwise a second one is created.")
        }
    }
}

$rows | Format-Table -AutoSize

foreach ($n in $notes) {
    Write-Host "note: $n" -ForegroundColor Yellow
    Write-Host ''
}

if (-not $rgOk -or -not $srvOk -or -not $dbOk) {
    Write-Host 'The resource group, logical server, and database belong to Chapter 2 and' -ForegroundColor Red
    Write-Host 'are shared by every chapter. This chapter never creates them. If one is' -ForegroundColor Red
    Write-Host 'missing, check RG, SRV, and WardGeneral__Database for a typo before' -ForegroundColor Red
    Write-Host 'assuming it is gone -- SRV is the SHORT name, not the FQDN.' -ForegroundColor Red
    Write-Host ''
    exit 1
}

if ($creates -eq 0) {
    Write-Host 'Everything this chapter needs already exists. deploy-ai.ps1 would create nothing.' -ForegroundColor Green
} else {
    Write-Host "deploy-ai.ps1 would create $creates resource(s), marked WILL BE CREATED above." -ForegroundColor Cyan
    Write-Host 'If something there was supposed to exist already, it is a typo in ch05.env' -ForegroundColor Cyan
    Write-Host 'or the wrong subscription - fix that before running the deploy.'           -ForegroundColor Cyan
}
Write-Host ''
