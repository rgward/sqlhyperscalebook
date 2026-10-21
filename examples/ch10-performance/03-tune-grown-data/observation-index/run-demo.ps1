<#
.SYNOPSIS
    Evaluates the Chapter 7 ValueNumeric missing-index recommendation on
    clinical.Observation: read benefit, write cost, and storage.

.DESCRIPTION
    Chapter 7's performance demo ends with a Query Store missing-index
    recommendation for clinical.Observation (key ValueNumeric, INCLUDE
    ObservationType) and says Chapter 10 weighs the trade-offs. This runner
    does that with measurements instead of assumptions:

      1. Drops this example's index if an earlier run left it behind.
      2. Runs the Chapter 7 query twice (the second run is the warm one we
         compare) and records logical reads and CPU/elapsed time.
      3. Measures write cost: 500 clinical.RecordVitals calls in one
         transaction, then ROLLBACK, recording the log bytes generated.
      4. Builds IX_Observation_ValueNumeric_Ch10 ONLINE and records its build
         time and size.
      5. Repeats steps 2 and 3 with the index in place.
      6. Drops the index again (unless -KeepIndex).

    Without -Execute it only previews. No clinical data is changed: the write
    measurement is rolled back.

.EXAMPLE
    ./run-demo.ps1
    ./run-demo.ps1 -Execute
    ./run-demo.ps1 -Execute -KeepIndex
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $Server,
    [string] $Database,
    [switch] $Execute,
    [switch] $KeepIndex
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

$readScript    = Join-Path $PSScriptRoot '01-measure-read.sql'
$writeScript   = Join-Path $PSScriptRoot '02-measure-write.sql'
$indexScript   = Join-Path $PSScriptRoot '03-create-index.sql'
$cleanupScript = Join-Path $PSScriptRoot '04-cleanup.sql'

Write-Host 'Chapter 10 Demo 3: evaluate the Chapter 7 ValueNumeric index' -ForegroundColor Cyan
Write-Host ("  Target database {0} @ {1}" -f $Database, $Server)
Write-Host '  Index           IX_Observation_ValueNumeric_Ch10 on clinical.Observation (ValueNumeric) INCLUDE (ObservationType)'
Write-Host '  Reads           the Chapter 7 query, before and after the index'
Write-Host '  Writes          500 RecordVitals calls in one transaction, ROLLED BACK, before and after'
Write-Host '  Build           ONLINE; on ~108 million rows expect several minutes and extra billed storage'
Write-Host ("  Cleanup         {0}" -f $(if ($KeepIndex) { 'KEEP the index (-KeepIndex); drop it later with 04-cleanup.sql' } else { 'drop the index when done' }))

if (-not $Execute) {
    Write-Host ''
    Write-Host 'Preview only. Rerun with -Execute to run the evaluation.' -ForegroundColor Yellow
    return
}

$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssZ')
$runDirectory = Join-Path $PSScriptRoot "results\runs\$runId"
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null

function Invoke-SqlScript {
    param([Parameter(Mandatory)] [string] $Script, [Parameter(Mandatory)] [string] $Name)
    $outputPath = Join-Path $runDirectory "$Name.txt"
    & $sqlcmd -S $Server -d $Database -G -b -W -i $Script -o $outputPath
    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd failed for $(Split-Path $Script -Leaf) with exit code $LASTEXITCODE. See $outputPath."
    }
    Get-Content -LiteralPath $outputPath -Raw
}

function Get-Marker {
    param([string] $Text, [string] $Marker)
    $m = [regex]::Match($Text, "$Marker\|([^\r\n]*)")
    if (-not $m.Success) { throw "Expected a $Marker line in the script output." }
    # The comma keeps a one-field result an array instead of a bare string.
    return ,($m.Groups[1].Value.Split('|'))
}

function Measure-Read {
    param([string] $Phase)
    $null = Invoke-SqlScript -Script $readScript -Name "$Phase-read-warmup"
    $text = Invoke-SqlScript -Script $readScript -Name "$Phase-read"
    $reads = [regex]::Matches($text,
        "Table '(?:\[clinical\]\.\[Observation\]|Observation)'\. Scan count \d+, logical reads (\d+)")
    $times = [regex]::Matches($text, 'CPU time = (\d+) ms,\s*elapsed time = (\d+) ms')
    $usage = Get-Marker $text 'CH10OBS_USAGE'
    [pscustomobject]@{
        LogicalReads = [int64](($reads | ForEach-Object { [int64]$_.Groups[1].Value } | Measure-Object -Sum).Sum)
        CpuMs        = [int64](($times | ForEach-Object { [int64]$_.Groups[1].Value } | Measure-Object -Maximum).Maximum)
        ElapsedMs    = [int64](($times | ForEach-Object { [int64]$_.Groups[2].Value } | Measure-Object -Maximum).Maximum)
        IndexSeeks   = [int64]$usage[0]
        IndexScans   = [int64]$usage[1]
    }
}

function Measure-Write {
    param([string] $Phase)
    $w = Get-Marker (Invoke-SqlScript -Script $writeScript -Name "$Phase-write") 'CH10OBS_WRITE'
    [pscustomobject]@{
        Rows      = [int]$w[0]
        LogBytes  = [int64]$w[1]
        ElapsedMs = [int64]$w[2]
    }
}

function Format-Change([double] $Before, [double] $After) {
    if ($Before -eq 0) { return 'n/a' }
    $pct = 100.0 * ($After - $Before) / $Before
    return ('{0:+0;-0;0}%' -f $pct)
}

try {
    $null = Invoke-SqlScript -Script $cleanupScript -Name '00-cleanup-before'

    Write-Host ''
    Write-Host 'Measuring reads and writes without the index...' -ForegroundColor Yellow
    $readBefore = Measure-Read 'before'
    $writeBefore = Measure-Write 'before'

    Write-Host 'Building IX_Observation_ValueNumeric_Ch10 ONLINE (this takes a while)...' -ForegroundColor Yellow
    $build = Get-Marker (Invoke-SqlScript -Script $indexScript -Name 'create-index') 'CH10OBS_INDEX'

    Write-Host 'Measuring reads and writes with the index...' -ForegroundColor Yellow
    $readAfter = Measure-Read 'after'
    $writeAfter = Measure-Write 'after'

    $perRowBefore = $writeBefore.LogBytes / [math]::Max($writeBefore.Rows, 1)
    $perRowAfter  = $writeAfter.LogBytes / [math]::Max($writeAfter.Rows, 1)

    $summary = [pscustomobject][ordered]@{
        Index = 'IX_Observation_ValueNumeric_Ch10'
        BuildSeconds = [math]::Round([int64]$build[0] / 1000.0, 1)
        IndexMB = [double]$build[1]
        TableMB = [double]$build[2]
        ReadBefore = $readBefore
        ReadAfter = $readAfter
        WriteBefore = $writeBefore
        WriteAfter = $writeAfter
        IndexUsedByQuery = ($readAfter.IndexSeeks + $readAfter.IndexScans) -gt 0
        KeptIndex = [bool]$KeepIndex
    }
    $summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runDirectory 'summary.json') -Encoding utf8NoBOM

    Write-Host ''
    Write-Host 'Result' -ForegroundColor Green
    $rows = @(
        [pscustomobject]@{ Measure = 'Query logical reads';      Before = '{0:N0}' -f $readBefore.LogicalReads; After = '{0:N0}' -f $readAfter.LogicalReads; Change = Format-Change $readBefore.LogicalReads $readAfter.LogicalReads }
        [pscustomobject]@{ Measure = 'Query CPU ms';             Before = '{0:N0}' -f $readBefore.CpuMs;        After = '{0:N0}' -f $readAfter.CpuMs;        Change = Format-Change $readBefore.CpuMs $readAfter.CpuMs }
        [pscustomobject]@{ Measure = 'Query elapsed ms';         Before = '{0:N0}' -f $readBefore.ElapsedMs;    After = '{0:N0}' -f $readAfter.ElapsedMs;    Change = Format-Change $readBefore.ElapsedMs $readAfter.ElapsedMs }
        [pscustomobject]@{ Measure = 'Log bytes per new row';    Before = '{0:N0}' -f $perRowBefore;            After = '{0:N0}' -f $perRowAfter;            Change = Format-Change $perRowBefore $perRowAfter }
        [pscustomobject]@{ Measure = '500 inserts, elapsed ms';  Before = '{0:N0}' -f $writeBefore.ElapsedMs;   After = '{0:N0}' -f $writeAfter.ElapsedMs;   Change = Format-Change $writeBefore.ElapsedMs $writeAfter.ElapsedMs }
    )
    $rows | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host ("  Index build: {0:N1} s; index size {1:N1} MB alongside a {2:N1} MB table ({3:N1}% more storage)" -f `
        $summary.BuildSeconds, $summary.IndexMB, $summary.TableMB,
        $(if ($summary.TableMB -gt 0) { 100.0 * $summary.IndexMB / $summary.TableMB } else { 0 }))
    Write-Host ("  The query {0} the new index (seeks {1}, scans {2})." -f `
        $(if ($summary.IndexUsedByQuery) { 'used' } else { 'did NOT use' }), $readAfter.IndexSeeks, $readAfter.IndexScans)
    Write-Host "  Evidence: $runDirectory" -ForegroundColor Gray
}
finally {
    if (-not $KeepIndex) {
        $clean = Get-Marker (Invoke-SqlScript -Script $cleanupScript -Name '99-cleanup') 'CH10OBS_CLEAN'
        Write-Host ("  Cleanup: demo index {0}." -f $clean[0]) -ForegroundColor Gray
    }
}
