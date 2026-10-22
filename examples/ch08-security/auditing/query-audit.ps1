<#
.SYNOPSIS
    Query a bounded UTC interval of Ward General auditing events.

.DESCRIPTION
    Loads query-audit.kql, substitutes the requested UTC interval and Ward
    General names, and queries the dedicated Chapter 8 Log Analytics workspace.
    This script is read-only.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [datetime] $StartUtc = [datetime]::UtcNow.AddMinutes(-30),
    [datetime] $EndUtc = [datetime]::UtcNow,
    [string] $ResourceGroup,
    [string] $WorkspaceName,
    [string] $Server,
    [string] $Database,
    [string] $Application = 'wardgeneral-app',
    [switch] $AllApplications,
    [switch] $Detailed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$here = $PSScriptRoot

$loadEnv = Join-Path $here '..' '..' 'ch04-first-app' 'load-env.ps1'
if (Test-Path $loadEnv) { & $loadEnv -Optional -Quiet }
if (-not $ResourceGroup) { $ResourceGroup = $env:RG ?? 'rg-collierhealth' }

if (-not $Server) { $Server = $env:WardGeneral__Server }
if (-not $Database) { $Database = $env:WardGeneral__Database ?? 'wardgeneral' }
if (-not $WorkspaceName) { $WorkspaceName = "$Database-ch08-audit" }
if ([string]::IsNullOrWhiteSpace($Server) -or $Server -match '<[^>]*>') {
    throw 'No server. Fill in WardGeneral__Server in examples/ch04-first-app/ch04.env, set the environment variable, or pass -Server explicitly.'
}
if ($EndUtc.ToUniversalTime() -le $StartUtc.ToUniversalTime()) {
    throw 'EndUtc must be later than StartUtc.'
}
$serverName = ($Server -split '\.')[0]

$workspace = az monitor log-analytics workspace list `
    --resource-group $ResourceGroup `
    --query "[?name=='$WorkspaceName'] | [0].{id:id,name:name,customerId:customerId,tags:tags}" `
    -o json | ConvertFrom-Json
if (-not $workspace) {
    throw "Workspace '$WorkspaceName' does not exist. Run setup-auditing.ps1 first."
}
$ownerTag = $workspace.tags.PSObject.Properties['hyperscalebook']?.Value
if ($ownerTag -ne 'ch08-auditing') {
    throw "Workspace '$WorkspaceName' does not carry the Chapter 8 ownership tag."
}

function ConvertTo-KqlString([string] $Value) {
    return $Value.Replace("'", "''")
}

$queryPath = Join-Path $here 'query-audit.kql'
$query = Get-Content -LiteralPath $queryPath -Raw
$query = $query.Replace('__START_UTC__', $StartUtc.ToUniversalTime().ToString('o'))
$query = $query.Replace('__END_UTC__', $EndUtc.ToUniversalTime().ToString('o'))
$query = $query.Replace('__DATABASE__', (ConvertTo-KqlString $Database))
$query = $query.Replace('__SERVER__', (ConvertTo-KqlString $serverName))
if ($AllApplications) {
    $query = $query.Replace("| where application_name_s =~ '__APPLICATION__'", '')
}
else {
    $query = $query.Replace('__APPLICATION__', (ConvertTo-KqlString $Application))
}

$logsToken = az account get-access-token `
    --resource https://api.loganalytics.io `
    --query accessToken -o tsv
$queryBody = @{
    query = $query
    timespan = '{0}/{1}' -f `
        $StartUtc.ToUniversalTime().ToString('o'), `
        $EndUtc.ToUniversalTime().ToString('o')
} | ConvertTo-Json
try {
    $response = Invoke-RestMethod `
        -Method Post `
        -Uri "https://api.loganalytics.io/v1/workspaces/$($workspace.customerId)/query" `
        -Headers @{ Authorization = "Bearer $logsToken" } `
        -ContentType 'application/json' `
        -Body $queryBody
}
catch {
    $detail = "$($_.ErrorDetails.Message)"
    # AzureDiagnostics creates the audit columns (event_time_t, ...) only when the
    # first audit record arrives, so until then the query cannot resolve them.
    if ($detail -match 'SEM0100' -and $detail -match 'Failed to resolve column') {
        Write-Host "No audit records have reached workspace '$WorkspaceName' yet; its audit columns appear with the first record." -ForegroundColor Yellow
        Write-Host 'A new audit destination can take up to 90 minutes to start receiving events. Open a chart again in a few minutes, then rerun.' -ForegroundColor Yellow
        return
    }
    if ($detail) { throw "Log Analytics rejected the audit query: $detail" }
    throw
}

$table = @($response.tables) | Select-Object -First 1
$rows = if ($table) {
    $columnNames = @($table.columns | ForEach-Object { $_.name })
    @($table.rows | ForEach-Object {
        $properties = [ordered]@{}
        for ($index = 0; $index -lt $columnNames.Count; $index++) {
            $properties[$columnNames[$index]] = $_[$index]
        }
        [pscustomobject] $properties
    })
}
else {
    @()
}

Write-Host 'Chapter 8 — Ward General Azure SQL Database Auditing' -ForegroundColor Cyan
Write-Host "Server    : $serverName" -ForegroundColor Gray
Write-Host "Database  : $Database" -ForegroundColor Gray
Write-Host "Application: $(if ($AllApplications) { '<all>' } else { $Application })" -ForegroundColor Gray
Write-Host "Workspace : $WorkspaceName" -ForegroundColor Gray
Write-Host "Window    : $($StartUtc.ToUniversalTime().ToString('u')) through $($EndUtc.ToUniversalTime().ToString('u'))" -ForegroundColor Gray
Write-Host ''

if (@($rows).Count -eq 0) {
    Write-Host 'No matching audit rows have arrived yet.' -ForegroundColor Yellow
    Write-Host 'Audit delivery is asynchronous. Wait a few minutes and rerun with the same UTC interval.' -ForegroundColor Yellow
    return
}

if ($Detailed) {
    $rows | Format-List EventTime, SessionId, ServerPrincipal,
        DatabasePrincipal, Action, Succeeded, Application, ClientIp, Statement,
        AdditionalInformation, DurationMs, ResponseRows
}
else {
    $rows | Format-Table EventTime, SessionId, ServerPrincipal,
    DatabasePrincipal, Action, Succeeded, Application, ClientIp, Statement `
        -Wrap -AutoSize
}
Write-Host ''
Write-Host "Returned $(@($rows).Count) audit row(s)." -ForegroundColor Green
