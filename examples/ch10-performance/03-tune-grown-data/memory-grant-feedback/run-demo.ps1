<#
.SYNOPSIS
    Runs the Ward General query-feedback demo and saves actual execution plans.

.EXAMPLE
    ./run-demo.ps1
    ./run-demo.ps1 -Execute
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $Server,
    [string] $Database,
    [switch] $Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$loadEnv = Join-Path $PSScriptRoot '..\..\..\ch04-first-app\load-env.ps1'
if (Test-Path $loadEnv) { & $loadEnv -Optional -Quiet }
if (-not $Server) { $Server = $env:WardGeneral__Server }
if (-not $Database) { $Database = $env:WardGeneral__Database }
if ([string]::IsNullOrWhiteSpace($Server) -or
    [string]::IsNullOrWhiteSpace($Database)) {
    throw 'Configure WardGeneral__Server and WardGeneral__Database or pass -Server and -Database.'
}

$sqlcmd = @(
    $env:SQLCMD,
    'C:\Program Files\SqlCmd\sqlcmd.exe',
    (Get-Command sqlcmd -ErrorAction SilentlyContinue).Source
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $sqlcmd) {
    throw 'The new sqlcmd was not found. Install it with: winget install --id Microsoft.Sqlcmd'
}

$setupScript = Join-Path $PSScriptRoot '01-setup.sql'
$runScript = Join-Path $PSScriptRoot '02-run.sql'
$cleanupScript = Join-Path $PSScriptRoot '03-cleanup.sql'
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssZ')
$runDirectory = Join-Path $PSScriptRoot "results\runs\$runId"
$rawOutputPath = Join-Path $runDirectory 'run-output.txt'

function Invoke-SqlScript {
    param(
        [Parameter(Mandatory)] [string] $Script,
        [string] $OutputPath
    )

    $arguments = @(
        '-S', $Server,
        '-d', $Database,
        '-G',
        '-b',
        '-W',
        '-y', '0',
        '-i', $Script
    )
    if ($OutputPath) { $arguments += @('-o', $OutputPath) }

    & $sqlcmd @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd failed for $Script with exit code $LASTEXITCODE."
    }
}

function Get-AttributeValue {
    param(
        [System.Xml.XmlNode] $Node,
        [Parameter(Mandatory)] [string] $Name
    )

    if (-not $Node -or -not $Node.Attributes[$Name]) { return $null }
    return $Node.Attributes[$Name].Value
}

Write-Host 'Chapter 10 Demo 3: query-processing feedback' -ForegroundColor Cyan
Write-Host ("  Target database {0} @ {1}" -f $Database, $Server)
Write-Host '  Creates five million demo-owned rows and a covering index.'
Write-Host '  Saves actual plans for executions 1 and 2, then removes all demo objects.'

if (-not $Execute) {
    Write-Host ''
    Write-Host 'Preview only. Rerun with -Execute to run the experiment.' -ForegroundColor Yellow
    return
}

New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null

try {
    Invoke-SqlScript -Script $cleanupScript
    Invoke-SqlScript -Script $setupScript
    Invoke-SqlScript -Script $runScript -OutputPath $rawOutputPath

    $rawOutput = Get-Content -LiteralPath $rawOutputPath -Raw
    $planMatches = [regex]::Matches(
        $rawOutput,
        '<ShowPlanXML\b.*?</ShowPlanXML>',
        [System.Text.RegularExpressions.RegexOptions]::Singleline)

    if ($planMatches.Count -lt 2) {
        throw "Expected at least two actual Showplan XML documents; found $($planMatches.Count)."
    }

    $planEvidence = for ($execution = 1; $execution -le 2; $execution++) {
        $planXmlText = $planMatches[$execution - 1].Value
        $planPath = Join-Path $runDirectory "execution-$execution.sqlplan"
        [System.IO.File]::WriteAllText(
            $planPath,
            $planXmlText,
            [System.Text.UTF8Encoding]::new($false))

        [xml] $planXml = $planXmlText
        $namespace = [System.Xml.XmlNamespaceManager]::new($planXml.NameTable)
        $namespace.AddNamespace('sp', $planXml.DocumentElement.NamespaceURI)

        $statement = $planXml.SelectSingleNode(
            "//sp:StmtSimple[contains(@StatementText, 'CHECKSUM_AGG')]",
            $namespace)
        if (-not $statement) {
            throw "Execution $execution plan does not contain the expected statement."
        }

        $memoryGrant = $statement.SelectSingleNode('sp:QueryPlan/sp:MemoryGrantInfo', $namespace)
        $timeStats = $statement.SelectSingleNode('sp:QueryPlan/sp:QueryTimeStats', $namespace)
        $sort = $statement.SelectSingleNode(".//sp:RelOp[@PhysicalOp='Sort']", $namespace)
        $spill = $sort.SelectSingleNode('sp:Warnings/sp:SpillToTempDb', $namespace)
        $runtime = $sort.SelectSingleNode(
            './/sp:RunTimeCountersPerThread[@Thread="0"]',
            $namespace)

        [pscustomobject]@{
            Execution = $execution
            PlanFile = Split-Path $planPath -Leaf
            SortWarning = [bool] $spill
            SpillLevel = Get-AttributeValue -Node $spill -Name 'SpillLevel'
            SpilledThreadCount = Get-AttributeValue -Node $spill -Name 'SpilledThreadCount'
            GrantedMemoryKB = Get-AttributeValue -Node $memoryGrant -Name 'GrantedMemory'
            MaxUsedMemoryKB = Get-AttributeValue -Node $memoryGrant -Name 'MaxUsedMemory'
            LastRequestedMemoryKB = Get-AttributeValue -Node $memoryGrant -Name 'LastRequestedMemory'
            MemoryGrantFeedback = Get-AttributeValue -Node $memoryGrant -Name 'IsMemoryGrantFeedbackAdjusted'
            ActualRows = Get-AttributeValue -Node $runtime -Name 'ActualRows'
            ElapsedMs = Get-AttributeValue -Node $timeStats -Name 'ElapsedTime'
            CpuMs = Get-AttributeValue -Node $timeStats -Name 'CpuTime'
        }
    }

    # Query Store feedback must be read before cleanup removes the query.
    $feedbackQuery = @"
SET NOCOUNT ON;
SELECT CONCAT(pf.feature_desc, N'|', pf.state_desc)
FROM sys.query_store_query AS q
JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
JOIN sys.query_store_plan_feedback AS pf ON pf.plan_id = p.plan_id
WHERE q.object_id = OBJECT_ID(N'clinical.DemonstrateMemoryGrantFeedback')
ORDER BY pf.create_time, pf.plan_feedback_id;
"@
    $feedbackRows = @(& $sqlcmd -S $Server -d $Database -G -b -W -h -1 -Q ($feedbackQuery -replace '\r?\n', ' ') |
        Where-Object { $_ -match '\|' } |
        ForEach-Object {
            $parts = $_.Split('|')
            [pscustomobject]@{ Feature = $parts[0].Trim(); State = $parts[1].Trim() }
        })
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd failed reading Query Store feedback (exit code $LASTEXITCODE)." }
    $feedbackPath = Join-Path $runDirectory 'query-store-feedback.csv'
    $feedbackRows | Export-Csv -LiteralPath $feedbackPath -NoTypeInformation

    $summaryPath = Join-Path $runDirectory 'plan-summary.csv'
    $planEvidence | Export-Csv -LiteralPath $summaryPath -NoTypeInformation

    Write-Host ''
    Write-Host 'Actual-plan evidence' -ForegroundColor Green
    foreach ($evidence in $planEvidence) {
        Write-Host ("  Execution {0}: Elapsed={1} ms; CPU={2} ms; SortWarning={3}; SpillLevel={4}; Grant={5:N2} MB; Used={6:N2} MB; MGF={7}; ActualRows={8}" -f
            $evidence.Execution,
            $(if ($evidence.ElapsedMs) { $evidence.ElapsedMs } else { 'n/a' }),
            $(if ($evidence.CpuMs) { $evidence.CpuMs } else { 'n/a' }),
            $evidence.SortWarning,
            $(if ($evidence.SpillLevel) { $evidence.SpillLevel } else { 'none' }),
            ([double] $evidence.GrantedMemoryKB / 1024.0),
            ([double] $evidence.MaxUsedMemoryKB / 1024.0),
            $evidence.MemoryGrantFeedback,
            $evidence.ActualRows)
    }

    $first = [double] ($planEvidence[0].ElapsedMs ?? 0)
    $second = [double] ($planEvidence[1].ElapsedMs ?? 0)
    if ($first -gt 0 -and $second -gt 0) {
        $change = 100.0 * ($first - $second) / $first
        $direction = if ($change -ge 0) { 'faster' } else { 'slower' }
        Write-Host ("  Execution 2 was {0:N0}% {1} than execution 1 ({2} ms -> {3} ms)." -f
            [Math]::Abs($change), $direction, $first, $second)
    }

    Write-Host ''
    Write-Host 'Query Store feedback (sys.query_store_plan_feedback)' -ForegroundColor Green
    if ($feedbackRows.Count -eq 0) {
        Write-Host '  No persisted feedback rows yet.'
    }
    foreach ($row in $feedbackRows) {
        Write-Host ("  {0}: {1}" -f $row.Feature, $row.State)
    }
    Write-Host ("Results: {0}" -f $runDirectory)
}
finally {
    Invoke-SqlScript -Script $cleanupScript
}