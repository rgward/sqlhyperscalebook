<#
.SYNOPSIS
    Run the Chapter 7 Hyperscale availability query with the new sqlcmd.

.DESCRIPTION
    Loads the shared Ward General configuration, resolves the database's Azure
    resource ID and region, verifies that sqlcmd is the new Go-based
    implementation, executes availability.sql with passwordless
    authentication, and retrieves the previous 24 hours of Azure Monitor
    availability, connection, firewall, and replication-lag metrics. Read-only.

.PARAMETER ResourceGroup
    Resource group containing the logical server. Defaults to RG, then
    rg-collierhealth.

.PARAMETER Server
    Azure SQL logical-server FQDN. Defaults to WardGeneral__Server, including a
    value loaded from examples/ch04-first-app/ch04.env when that file exists.

.PARAMETER Database
    Database name. Defaults to WardGeneral__Database, then wardgeneral.

.PARAMETER SqlCmd
    Explicit path to the new sqlcmd executable. Defaults to SQLCMD, standard
    install locations, and the sqlcmd command on PATH.

.PARAMETER OutputDirectory
    Directory for the Azure Monitor metric evidence. Defaults to a timestamped
    folder beneath the current user's temporary directory.

.EXAMPLE
    ./run-availability.ps1

.EXAMPLE
    ./run-availability.ps1 -Server '<your-server>.database.windows.net'
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $ResourceGroup,
    [string] $Server,
    [string] $Database,
    [string] $SqlCmd,
    [string] $OutputDirectory
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
if ([string]::IsNullOrWhiteSpace($Server) -or $Server -match '<[^>]*>') {
    throw 'No server. Fill in WardGeneral__Server in examples/ch04-first-app/ch04.env, set the environment variable, or pass -Server <your-server>.database.windows.net.'
}
$serverName = ($Server -split '\.')[0]

try {
    $subscription = az account show --query '{name:name, id:id}' -o json |
        ConvertFrom-Json
}
catch {
    throw "Not signed in to Azure. Run 'az login' and select the subscription containing '$ResourceGroup'."
}

$databaseResource = az sql db show `
    --resource-group $ResourceGroup `
    --server $serverName `
    --name $Database `
    --query '{id:id, location:location}' `
    -o json | ConvertFrom-Json

$locations = @(az account list-locations -o json | ConvertFrom-Json)
$location = $locations | Where-Object { $_.name -ieq $databaseResource.location } |
    Select-Object -First 1
# StrictMode: $location can be $null, and a match might not carry displayName.
$regionDisplayName = if ($location -and $location.PSObject.Properties['displayName'] -and $location.displayName) {
    $location.displayName
}
else {
    $databaseResource.location
}

$isNewSqlcmd = {
    param([string] $Executable)
    if (-not $Executable) { return $false }
    & $Executable --version 2>&1 | Out-Null
    return $LASTEXITCODE -eq 0
}

$sqlcmdPath = @(
    $SqlCmd,
    $env:SQLCMD,
    (Join-Path $env:LOCALAPPDATA 'Programs\sqlcmd\sqlcmd.exe'),
    'C:\Program Files\SqlCmd\sqlcmd.exe',
    (Get-Command sqlcmd -ErrorAction SilentlyContinue).Source
) | Where-Object { $_ -and (Test-Path $_) -and (& $isNewSqlcmd $_) } |
    Select-Object -First 1

if (-not $sqlcmdPath) {
    throw @'
The new sqlcmd was not found. Install it with:

  winget install --id Microsoft.Sqlcmd

Then open a new PowerShell session, or set SQLCMD to its full path. The
executable name is sqlcmd; the legacy ODBC implementation is rejected because
it does not support the passwordless authentication flow used here.
'@
}

$queryPath = Join-Path $here 'availability.sql'
if (-not (Test-Path $queryPath)) { throw "Missing SQL script: $queryPath" }

if (-not $OutputDirectory) {
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $OutputDirectory = Join-Path ([IO.Path]::GetTempPath()) "wardgeneral-ch07-availability-$stamp"
}
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$OutputDirectory = (Resolve-Path $OutputDirectory).Path
$metricsOutput = Join-Path $OutputDirectory 'azure-monitor-availability.json'

Write-Host 'Chapter 7 — observe Hyperscale availability' -ForegroundColor Cyan
Write-Host "Subscription : $($subscription.name)  ($($subscription.id))" -ForegroundColor Gray
Write-Host "Resource ID  : $($databaseResource.id)" -ForegroundColor Gray
Write-Host "Region       : $regionDisplayName  ($($databaseResource.location))" -ForegroundColor Gray
Write-Host "Server   : $Server" -ForegroundColor Gray
Write-Host "Database : $Database" -ForegroundColor Gray
Write-Host "sqlcmd   : $sqlcmdPath" -ForegroundColor Gray
Write-Host "Evidence : $OutputDirectory" -ForegroundColor Gray
Write-Host ''

$arguments = @(
    '-S', $Server,
    '-d', $Database,
    '-G', '-C', '-b',
    '-i', $queryPath
)
& $sqlcmdPath @arguments

if ($LASTEXITCODE -ne 0) {
    throw "sqlcmd exited with code $LASTEXITCODE."
}

Write-Host ''
Write-Host '=== 4. Azure Monitor availability evidence — previous 24 hours ===' -ForegroundColor Cyan
$endTimeUtc = [DateTime]::UtcNow
$startTimeUtc = $endTimeUtc.AddHours(-24)
$commonMetricArguments = @(
    'monitor', 'metrics', 'list',
    '--subscription', $subscription.id,
    '--resource', $databaseResource.id,
    '--interval', 'PT1M',
    '--start-time', $startTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ'),
    '--end-time', $endTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ'),
    '-o', 'json'
)

$availabilityResult = az @commonMetricArguments `
    --metrics availability `
    --aggregation Average Minimum | ConvertFrom-Json
$connectionResult = az @commonMetricArguments `
    --metrics connection_successful connection_failed connection_failed_user_error blocked_by_firewall `
    --aggregation Total | ConvertFrom-Json
$replicationResult = az @commonMetricArguments `
    --metrics replication_lag_seconds `
    --aggregation Average Maximum | ConvertFrom-Json

# A metric the database doesn't emit can come back without a value array (or as
# nothing at all); under StrictMode reading .value on that throws.
function Get-MetricValues([object] $Result) {
    if ($Result -and $Result.PSObject.Properties['value']) { @($Result.value) } else { @() }
}

$metricEvidence = [pscustomobject][ordered]@{
    ResourceId = $databaseResource.id
    Region = $databaseResource.location
    WindowStartUtc = $startTimeUtc.ToString('o')
    WindowEndUtc = $endTimeUtc.ToString('o')
    Metrics = @(
        Get-MetricValues $availabilityResult
        Get-MetricValues $connectionResult
        Get-MetricValues $replicationResult
    )
}
$metricEvidence | ConvertTo-Json -Depth 20 |
    Set-Content -LiteralPath $metricsOutput -Encoding utf8NoBOM

function Get-MetricPointValue {
    param(
        [object] $Point,
        [string] $PropertyName
    )
    $property = $Point.PSObject.Properties[$PropertyName]
    if ($property) { $property.Value }
}

$metricSummary = foreach ($metric in $metricEvidence.Metrics) {
    $series = if ($metric.PSObject.Properties['timeseries']) { $metric.timeseries } else { @() }
    $points = @($series | ForEach-Object { if ($_.PSObject.Properties['data']) { $_.data } })
    $metricName = $metric.name.value
    if ($metricName -eq 'availability') {
        $minimumValues = @($points | ForEach-Object {
            Get-MetricPointValue -Point $_ -PropertyName 'minimum'
        } |
            Where-Object { $null -ne $_ })
        $averageValues = @($points | ForEach-Object {
            Get-MetricPointValue -Point $_ -PropertyName 'average'
        } |
            Where-Object { $null -ne $_ })
        [pscustomobject]@{
            Metric = $metricName
            Samples = $averageValues.Count
            Minimum = if ($minimumValues.Count) {
                ($minimumValues | Measure-Object -Minimum).Minimum
            } else { $null }
            Maximum = if ($averageValues.Count) {
                ($averageValues | Measure-Object -Maximum).Maximum
            } else { $null }
            Total = $null
        }
    }
    elseif ($metricName -eq 'replication_lag_seconds') {
        $averageValues = @($points | ForEach-Object {
            Get-MetricPointValue -Point $_ -PropertyName 'average'
        } |
            Where-Object { $null -ne $_ })
        $maximumValues = @($points | ForEach-Object {
            Get-MetricPointValue -Point $_ -PropertyName 'maximum'
        } |
            Where-Object { $null -ne $_ })
        [pscustomobject]@{
            Metric = $metricName
            Samples = $averageValues.Count
            Minimum = if ($averageValues.Count) {
                ($averageValues | Measure-Object -Minimum).Minimum
            } else { $null }
            Maximum = if ($maximumValues.Count) {
                ($maximumValues | Measure-Object -Maximum).Maximum
            } else { $null }
            Total = $null
        }
    }
    else {
        $totalValues = @($points | ForEach-Object {
            Get-MetricPointValue -Point $_ -PropertyName 'total'
        } |
            Where-Object { $null -ne $_ })
        [pscustomobject]@{
            Metric = $metricName
            Samples = $totalValues.Count
            Minimum = $null
            Maximum = $null
            Total = if ($totalValues.Count) {
                ($totalValues | Measure-Object -Sum).Sum
            } else { $null }
        }
    }
}
$metricSummary | Format-Table Metric, Samples, Minimum, Maximum, Total -AutoSize
Write-Host "Metric window (UTC): $($metricEvidence.WindowStartUtc) through $($metricEvidence.WindowEndUtc)" -ForegroundColor Green
Write-Host "Metric evidence    : $metricsOutput" -ForegroundColor Gray

# --- Platform health: Resource Health and exact-region Service Health ---------
# Read-only GETs through az rest. Query parameters go through --url-parameters:
# a literal '&' in the URL is split by az.cmd on Windows. A failure here is
# reported as unavailable, not fatal - the SQL and metric evidence still stand.
Write-Host ''
Write-Host '=== 5. Platform health — Resource Health and Service Health ===' -ForegroundColor Cyan
$healthApi = 'api-version=2022-10-01'
$resourceHealthOutput = Join-Path $OutputDirectory 'resource-health.json'
$serviceHealthOutput  = Join-Path $OutputDirectory 'service-health.json'

function Invoke-ArmGet {
    param([string] $Url, [string[]] $UrlParameters)
    $previous = $PSNativeCommandUseErrorActionPreference
    $previousEncoding = $env:PYTHONIOENCODING
    $PSNativeCommandUseErrorActionPreference = $false
    # Event text can contain characters the console code page can't encode;
    # UTF-8 keeps az from dropping them and warning on stderr.
    $env:PYTHONIOENCODING = 'utf-8'
    try {
        $all = @(az rest --method get --url $Url --url-parameters @UrlParameters -o json 2>&1)
        $ok = $LASTEXITCODE -eq 0
    }
    finally {
        $PSNativeCommandUseErrorActionPreference = $previous
        $env:PYTHONIOENCODING = $previousEncoding
    }
    $stdout = @($all | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
    $stderr = @($all | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    if ($ok) { return [pscustomobject]@{ Ok = $true; Body = ($stdout | Out-String | ConvertFrom-Json); Error = $null } }
    return [pscustomobject]@{ Ok = $false; Body = $null; Error = ((@($stderr) + @($stdout)) | Out-String).Trim() }
}

function Get-Prop {
    param([object] $Object, [string] $Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { $property.Value }
}

$statusCall = Invoke-ArmGet -Url "https://management.azure.com$($databaseResource.id)/providers/Microsoft.ResourceHealth/availabilityStatuses/current" -UrlParameters @($healthApi)
if ($statusCall.Ok) {
    $p = Get-Prop $statusCall.Body 'properties'
    $resourceHealth = [pscustomobject][ordered]@{
        ResourceId        = $databaseResource.id
        AvailabilityState = Get-Prop $p 'availabilityState'
        Summary           = Get-Prop $p 'summary'
        OccurredTime      = Get-Prop $p 'occuredTime'
        ReportedTime      = Get-Prop $p 'reportedTime'
    }
    Write-Host "Resource Health : $($resourceHealth.AvailabilityState) — $($resourceHealth.Summary)" -ForegroundColor Green
    Write-Host "                  occurred $($resourceHealth.OccurredTime); reported $($resourceHealth.ReportedTime)" -ForegroundColor Gray
}
else {
    $resourceHealth = [pscustomobject]@{ ResourceId = $databaseResource.id; Unavailable = $statusCall.Error }
    Write-Host "Resource Health : unavailable — $($statusCall.Error)" -ForegroundColor Yellow
}
$resourceHealth | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resourceHealthOutput -Encoding utf8NoBOM

$serviceWindowStart = $endTimeUtc.AddDays(-30)
$eventsCall = Invoke-ArmGet -Url "https://management.azure.com/subscriptions/$($subscription.id)/providers/Microsoft.ResourceHealth/events" `
    -UrlParameters @($healthApi, "queryStartTime=$($serviceWindowStart.ToString('yyyy-MM-ddTHH:mm:ssZ'))")
if ($eventsCall.Ok) {
    # Match the skill's rule exactly: the service is Azure SQL Database AND the
    # database's own region is impacted. Similar names and other regions don't count.
    $allEvents = @(Get-Prop $eventsCall.Body 'value')
    $matching = @(foreach ($svcEvent in $allEvents) {
        $props = Get-Prop $svcEvent 'properties'
        $sqlImpact = @(Get-Prop $props 'impact') | Where-Object { (Get-Prop $_ 'impactedService') -eq 'Azure SQL Database' }
        $regions = @($sqlImpact | ForEach-Object { Get-Prop $_ 'impactedRegions' } | ForEach-Object { Get-Prop $_ 'impactedRegion' })
        if ($regions | Where-Object { $_ -ieq $regionDisplayName }) {
            [pscustomobject][ordered]@{
                TrackingId     = Get-Prop $svcEvent 'name'
                EventType      = Get-Prop $props 'eventType'
                Status         = Get-Prop $props 'status'
                Title          = Get-Prop $props 'title'
                LastUpdateTime = Get-Prop $props 'lastUpdateTime'
            }
        }
    })
    $serviceHealth = [pscustomobject][ordered]@{
        WindowStartUtc   = $serviceWindowStart.ToString('o')
        WindowEndUtc     = $endTimeUtc.ToString('o')
        Service          = 'Azure SQL Database'
        Region           = $regionDisplayName
        EventsReturned   = $allEvents.Count
        MatchingEvents   = $matching
    }
    Write-Host "Service Health  : $($matching.Count) Azure SQL Database event(s) in $regionDisplayName over the last 30 days ($($serviceHealth.EventsReturned) subscription event(s) checked)" -ForegroundColor Green
    if ($matching.Count) { $matching | Format-Table EventType, Status, LastUpdateTime, Title -AutoSize }
}
else {
    $serviceHealth = [pscustomobject]@{ Region = $regionDisplayName; Unavailable = $eventsCall.Error }
    Write-Host "Service Health  : unavailable — $($eventsCall.Error)" -ForegroundColor Yellow
}
$serviceHealth | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $serviceHealthOutput -Encoding utf8NoBOM
Write-Host "Health evidence : $resourceHealthOutput" -ForegroundColor Gray
Write-Host "                  $serviceHealthOutput" -ForegroundColor Gray