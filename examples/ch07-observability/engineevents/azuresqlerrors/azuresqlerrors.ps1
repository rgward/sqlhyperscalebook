<#
.SYNOPSIS
    Display retained Azure SQL error events for the Ward General database.

.DESCRIPTION
    Loads the server and database names from the existing Chapter 4 ch04.env,
    resolves the exact Azure SQL database resource, discovers a Log Analytics
    workspace from its diagnostic settings, and queries AzureSQLErrors for the
    requested UTC lookback window.

    The script is read-only. It does not create a workspace or diagnostic
    setting. Azure SQL resource logs are not retained until a diagnostic setting
    routes them to Log Analytics.

.PARAMETER Hours
    UTC lookback in hours. Defaults to 24.

.PARAMETER WorkspaceResourceId
    Optional Log Analytics workspace ARM resource ID. Use this when the workspace
    cannot be discovered from a diagnostic setting on the database or logical
    server.

.PARAMETER Server
    Azure SQL logical-server FQDN. Defaults to WardGeneral__Server, including a
    value loaded from examples/ch04-first-app/ch04.env.

.PARAMETER Database
    Database name. Defaults to WardGeneral__Database, then wardgeneral.

.PARAMETER Wait
    Raise the test error (generate-azuresqlerror.sql), check AzureSQLErrors for
    it, and repeat every WaitIntervalSeconds until it arrives or WaitMinutes
    pass. Azure starts sending a new diagnostic setting's events after anything
    from a few minutes to a few hours, and errors raised before then are never
    retained, so a single test error can be lost. Use -Wait right after setup.

.PARAMETER WaitMinutes
    How long -Wait keeps trying. Defaults to 180.

.PARAMETER WaitIntervalSeconds
    Time between -Wait attempts. Defaults to 300.

.PARAMETER SqlCmd
    Path to the new sqlcmd, used by -Wait to raise the test error.

.EXAMPLE
    ./azuresqlerrors.ps1

.EXAMPLE
    ./azuresqlerrors.ps1 -Wait

.EXAMPLE
    ./azuresqlerrors.ps1 -Hours 72 -WorkspaceResourceId '<workspace-resource-id>'
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateRange(1, 720)]
    [int] $Hours = 24,
    [string] $WorkspaceResourceId,
    [string] $Server,
    [string] $Database,
    [switch] $Wait,
    [ValidateRange(1, 720)]
    [int] $WaitMinutes = 180,
    [ValidateRange(1, 3600)]
    [int] $WaitIntervalSeconds = 300,
    [string] $SqlCmd
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$here = $PSScriptRoot

$loadEnv = Join-Path $here '..' '..' '..' 'ch04-first-app' 'load-env.ps1'
if (Test-Path $loadEnv) { & $loadEnv -Optional -Quiet }

if (-not $Server) { $Server = $env:WardGeneral__Server }
if (-not $Database) { $Database = $env:WardGeneral__Database ?? 'wardgeneral' }
if ([string]::IsNullOrWhiteSpace($Server) -or $Server -match '<[^>]*>') {
    throw 'No server. Fill in WardGeneral__Server in examples/ch04-first-app/ch04.env, set the environment variable, or pass -Server explicitly.'
}
$serverName = ($Server -split '\.')[0]

try {
    $subscriptions = @(az account list --query "[?state=='Enabled'].id" -o tsv)
    $managementToken = az account get-access-token `
        --resource https://management.azure.com/ `
        --query accessToken -o tsv
}
catch {
    throw "Not signed in to Azure. Run 'az login', then run this script again."
}

$resourceGraphQuery = @"
resources
| where type =~ 'microsoft.sql/servers/databases'
| where name =~ '$Database'
| where id endswith '/servers/$serverName/databases/$Database'
| project id, subscriptionId, resourceGroup, location
"@
$resourceGraphBody = @{
    subscriptions = $subscriptions
    query = $resourceGraphQuery
    options = @{ resultFormat = 'objectArray' }
} | ConvertTo-Json -Depth 4
$resourceGraphResult = Invoke-RestMethod `
    -Method Post `
    -Uri 'https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' `
    -Headers @{ Authorization = "Bearer $managementToken" } `
    -ContentType 'application/json' `
    -Body $resourceGraphBody
$databaseResource = @($resourceGraphResult.data) | Select-Object -First 1
if (-not $databaseResource) {
    throw "Could not find Azure SQL database $serverName/$Database in the subscriptions visible to Azure CLI."
}

$serverResourceId = $databaseResource.id -replace '/databases/[^/]+$', ''
if (-not $WorkspaceResourceId) {
    $databaseSettings = az monitor diagnostic-settings list `
        --resource $databaseResource.id -o json | ConvertFrom-Json
    $serverSettings = az monitor diagnostic-settings list `
        --resource $serverResourceId -o json | ConvertFrom-Json
    $diagnosticSettings = @($databaseSettings) + @($serverSettings)
    if ($diagnosticSettings.Count -eq 1) {
        $valueProperty = $diagnosticSettings[0].PSObject.Properties['value']
        if ($valueProperty) {
            $diagnosticSettings = @($valueProperty.Value)
        }
    }
    $WorkspaceResourceId = $diagnosticSettings |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.workspaceId) } |
        Select-Object -ExpandProperty workspaceId -First 1
}

if ([string]::IsNullOrWhiteSpace($WorkspaceResourceId)) {
    throw @"
No Log Analytics workspace is configured in a diagnostic setting on
$serverName/$Database or its logical server. ch04.env identifies the database,
but it does not identify a log destination.

Create a diagnostic setting that routes the Azure SQL error/workload log
category to Log Analytics, or rerun with:

  -WorkspaceResourceId '<workspace-resource-id>'

Diagnostic export is not enabled by this read-only script.
"@
}

$workspace = az resource show `
    --ids $WorkspaceResourceId `
    --query '{name:name, customerId:properties.customerId}' `
    -o json | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($workspace.customerId)) {
    throw "Could not resolve the Log Analytics workspace customer ID from $WorkspaceResourceId."
}

$databaseResourceId = $databaseResource.id.ToLowerInvariant()
$query = @"
AzureSQLErrors
| where TimeGenerated >= ago(${Hours}h)
| where DatabaseName =~ '$Database'
| where _ResourceId =~ '$databaseResourceId'
| project TimeGenerated, ErrorNumber, Severity, State, UserDefined,
          Message, QueryHash, QueryPlanHash, OperationName
| order by TimeGenerated desc
"@

Write-Host 'Chapter 7 — retained Azure SQL engine errors' -ForegroundColor Cyan
Write-Host "Database  : $serverName/$Database" -ForegroundColor Gray
Write-Host "Resource  : $($databaseResource.id)" -ForegroundColor Gray
Write-Host "Workspace : $($workspace.name)" -ForegroundColor Gray
Write-Host "Window    : previous $Hours hours (UTC)" -ForegroundColor Gray
Write-Host ''

function Get-AzureSqlErrorRows {
    try {
        $logsToken = az account get-access-token `
            --resource https://api.loganalytics.io `
            --query accessToken -o tsv
        # ISO 8601 duration: hours need the time designator (PT2H). Log Analytics
        # accepts "P2H" without an error but treats it as an empty window, so every
        # query returned no rows.
        $queryBody = @{
            query = $query
            timespan = "PT${Hours}H"
        } | ConvertTo-Json
        $queryResponse = Invoke-RestMethod `
            -Method Post `
            -Uri "https://api.loganalytics.io/v1/workspaces/$($workspace.customerId)/query" `
            -Headers @{ Authorization = "Bearer $logsToken" } `
            -ContentType 'application/json' `
            -Body $queryBody

        $table = @($queryResponse.tables) | Select-Object -First 1
        $result = if ($table) {
            $columnNames = @($table.columns | ForEach-Object { $_.name })
            foreach ($row in $table.rows) {
                $properties = [ordered]@{}
                for ($index = 0; $index -lt $columnNames.Count; $index++) {
                    $properties[$columnNames[$index]] = $row[$index]
                }
                [pscustomobject]$properties
            }
        }
        else {
            @()
        }
    }
    catch {
        throw @"
The AzureSQLErrors query failed. Confirm that the diagnostic setting uses the
resource-specific destination schema and that the workspace contains the
AzureSQLErrors table. A database-level Errors category using Azure Diagnostics
mode writes to AzureDiagnostics instead.

$($_.Exception.Message)
"@
    }
    @($result)
}

if ($Wait) {
    # A new diagnostic setting starts sending at an unpredictable moment
    # (minutes, occasionally hours), and errors raised before then are never
    # retained. So raise the test error, check for it, and repeat until it arrives.
    $isNewSqlcmd = {
        param([string] $Executable)
        if (-not $Executable) { return $false }
        & $Executable --version 2>&1 | Out-Null
        return $LASTEXITCODE -eq 0
    }
    $sqlcmdPath = @(
        $SqlCmd,
        $env:SQLCMD,
        $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs\sqlcmd\sqlcmd.exe' }),
        'C:\Program Files\SqlCmd\sqlcmd.exe',
        (Get-Command sqlcmd -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
    ) | Where-Object { $_ -and (Test-Path $_) -and (& $isNewSqlcmd $_) } |
        Select-Object -First 1
    if (-not $sqlcmdPath) {
        throw 'The new sqlcmd was not found. Install it with: winget install --id Microsoft.Sqlcmd, or set SQLCMD to its full path.'
    }
    $generatePath = Join-Path $here 'generate-azuresqlerror.sql'
    $marker = 'CH07_ENGINEEVENTS_AZURESQLERRORS_TEST'
    $deadline = (Get-Date).AddMinutes($WaitMinutes)
    $attempt = 0
    while ($true) {
        $attempt++
        $previous = $PSNativeCommandUseErrorActionPreference
        $PSNativeCommandUseErrorActionPreference = $false
        try { $raised = & $sqlcmdPath -S $Server -d $Database -G -C -i $generatePath 2>&1 | Out-String }
        finally { $PSNativeCommandUseErrorActionPreference = $previous }
        if ($raised -notmatch [regex]::Escape($marker)) {
            throw "Could not raise the test error on $serverName/$Database. sqlcmd said:`n$raised"
        }
        Write-Host ("[{0:HH:mm} UTC] Raised test error 50001 (attempt {1})." -f [DateTime]::UtcNow, $attempt) -ForegroundColor Gray
        $rows = @(Get-AzureSqlErrorRows)
        if (@($rows | Where-Object { $_.Message -eq $marker }).Count -gt 0) {
            Write-Host 'The test error has arrived in AzureSQLErrors.' -ForegroundColor Green
            Write-Host ''
            break
        }
        if ((Get-Date).AddSeconds($WaitIntervalSeconds) -gt $deadline) {
            Write-Host "The test error had not arrived after $WaitMinutes minutes." -ForegroundColor Yellow
            Write-Host 'Azure has not started sending this database''s errors yet. Confirm the diagnostic setting with setup-azuresqlerrors.ps1, then run this again later; the setup stays in place.' -ForegroundColor Yellow
            break
        }
        Write-Host ("  Not in AzureSQLErrors yet. Azure takes from a few minutes to a few hours to start sending a new database's errors, and errors raised before then are not kept. Checking again in {0} minute(s)..." -f [Math]::Max(1, [int]($WaitIntervalSeconds / 60))) -ForegroundColor DarkGray
        Start-Sleep -Seconds $WaitIntervalSeconds
    }
}
else {
    $rows = @(Get-AzureSqlErrorRows)
}
if ($rows.Count -eq 0) {
    Write-Host "No AzureSQLErrors rows were returned for $Database in the previous $Hours hours." -ForegroundColor Yellow
    Write-Host 'This means no retained rows matched the query; it does not prove that the application saw no errors.' -ForegroundColor Yellow
    Write-Host 'Severity 11-15 errors are generally excluded. For a qualifying severity-16+ error, check ingestion delay, diagnostic routing, and telemetry throttling.' -ForegroundColor Yellow
    return
}

$rows | Select-Object TimeGenerated, ErrorNumber, Severity, State, UserDefined,
    Message, QueryHash, QueryPlanHash, OperationName |
    Format-Table -Wrap -AutoSize
Write-Host ''
Write-Host ("Returned {0} AzureSQLErrors row(s)." -f $rows.Count) -ForegroundColor Green