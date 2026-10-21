#requires -Version 7.0
<#
.SYNOPSIS
    Runs the automated test suite for the book's examples.

.DESCRIPTION
    Two tiers:

    OFFLINE (default)  Fast checks that need no Azure subscription: repository
                       validation, skills and book prompts, links and anchors,
                       repository conventions, and script behavior with mocked
                       az / sqlcmd (preview modes change nothing, cross-platform
                       paths). LocalDB checks run when LocalDB is available.
                       Runs in CI on every push.

    LIVE (-Live)       Builds a separate copy of the book's environment with the
                       book's names (rg-collierhealth, collierhealth-<suffix>,
                       wardgeneral, wardgeneral-research), runs every chapter's
                       examples against it in book order, and deletes what it
                       created. Billable. Reads tests/test.env.

    Without -AcceptCharges, -Live only validates tests/test.env, checks the
    target, and prints the plan. Nothing is created.

.PARAMETER Live
    Run the live tier instead of the offline tier.

.PARAMETER Chapter
    Live tier: run only these chapters (2-10). Chapters after 2 need the
    database, so a later chapter on its own expects an environment kept from an
    earlier run with -KeepEnvironment.

.PARAMETER EnvFile
    Live tier: the tester's environment file. Default: tests/test.env.

.PARAMETER AcceptCharges
    Live tier: create billable Azure resources and run the examples.

.PARAMETER KeepEnvironment
    Live tier: leave the environment in place afterwards (it keeps billing).

.PARAMETER NoGateway
    Live tier: run Chapter 5 without API Management and content safety (saves
    the 30-45 minute APIM provision; skips the gateway-only proofs).

.PARAMETER ExcludeTag
    Pester tags to skip, for example Geo, Tde, Sqlsim.

.PARAMETER OutputDirectory
    Where results and evidence go. Default: tests/results/<tier>-<utc>.

.EXAMPLE
    ./tests/Invoke-BookTests.ps1

.EXAMPLE
    ./tests/Invoke-BookTests.ps1 -Live                 # plan only
    ./tests/Invoke-BookTests.ps1 -Live -AcceptCharges  # everything, then tear down
#>
[CmdletBinding()]
param(
    [switch] $Live,
    [string[]] $Chapter,
    [string] $EnvFile,
    [switch] $AcceptCharges,
    [switch] $KeepEnvironment,
    [switch] $NoGateway,
    [string[]] $ExcludeTag = @(),
    [string] $OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repo = Split-Path $here -Parent

# `pwsh -File` passes "-ExcludeTag Geo,Tde" as one string; accept both forms.
$ExcludeTag = @($ExcludeTag | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
[int[]] $chapterNumbers = @($Chapter | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object {
        $n = 0
        if (-not [int]::TryParse($_, [ref]$n) -or $n -lt 2 -or $n -gt 10) { throw "-Chapter takes chapter numbers 2 through 10; got '$_'." }
        $n
    })

$pester = Get-Module -ListAvailable Pester | Where-Object { $_.Version -ge [version]'5.5.0' } |
    Sort-Object Version -Descending | Select-Object -First 1
if (-not $pester) {
    throw 'Pester 5.5 or later is required. Install it with: Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -Force -SkipPublisherCheck'
}
Import-Module $pester -Force
Import-Module (Join-Path $here 'lib' 'BookTest.psm1') -Force

$tier = if ($Live) { 'live' } else { 'offline' }
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $here 'results' ("{0}-{1}" -f $tier, [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory = (Resolve-Path $OutputDirectory).Path

function Invoke-BookPester {
    param([string[]] $Path, [string] $Name, [switch] $StopBlockOnFailure)
    $config = New-PesterConfiguration
    $config.Run.Path = $Path
    $config.Run.PassThru = $true
    $config.Output.Verbosity = if ($Live) { 'Detailed' } else { 'Normal' }
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputFormat = 'NUnitXml'
    $config.TestResult.OutputPath = Join-Path $OutputDirectory "$Name.xml"
    if ($ExcludeTag) { $config.Filter.ExcludeTag = $ExcludeTag }
    # Live steps inside a Describe depend on each other: after a failure, skip the rest of that block.
    if ($StopBlockOnFailure) { $config.Run.SkipRemainingOnFailure = 'Block' }
    Invoke-Pester -Configuration $config
}

function Get-FailureCount {
    # FailedCount omits files that fail to load and failing BeforeAll/AfterAll blocks.
    param([object] $Result)
    if (-not $Result) { return 0 }
    $Result.FailedCount + $Result.FailedBlocksCount + $Result.FailedContainersCount
}

function Write-Summary {
    param([object[]] $Results)
    $passed = ($Results | Measure-Object -Property PassedCount -Sum).Sum
    $failed = ($Results | ForEach-Object { Get-FailureCount $_ } | Measure-Object -Sum).Sum
    $skipped = ($Results | Measure-Object -Property SkippedCount -Sum).Sum
    $lines = @(
        "Book test suite ($tier) - $([DateTime]::UtcNow.ToString('u'))",
        "Passed: $passed  Failed: $failed  Skipped: $skipped",
        "Results: $OutputDirectory"
    )
    foreach ($r in $Results) {
        foreach ($t in @($r.Failed)) { $lines += "FAILED  $($t.ExpandedPath)" }
        foreach ($b in @($r.FailedBlocks)) { $lines += "FAILED  block: $($b.ExpandedPath)" }
        foreach ($c in @($r.FailedContainers)) { $lines += "FAILED  file: $($c.Item)" }
    }
    $lines | Set-Content -LiteralPath (Join-Path $OutputDirectory 'summary.txt') -Encoding utf8NoBOM
    Write-Host ''
    $lines | ForEach-Object { Write-Host $_ -ForegroundColor $(if ($failed) { 'Red' } else { 'Green' }) }
    [int]$failed
}

# ---------------------------------------------------------------------------
# Offline tier
# ---------------------------------------------------------------------------
if (-not $Live) {
    $result = Invoke-BookPester -Path (Join-Path $here 'offline') -Name 'offline'
    $failed = Write-Summary @($result)
    exit $(if ($failed) { 1 } else { 0 })
}

# ---------------------------------------------------------------------------
# Live tier
# ---------------------------------------------------------------------------
if (-not $EnvFile) { $EnvFile = Join-Path $here 'test.env' }
$allChapters = 2..10
$chapters = if ($chapterNumbers.Count) { @($chapterNumbers | Sort-Object -Unique) } else { $allChapters }

$required = [Collections.Generic.List[string]]::new()
foreach ($k in 'SUBSCRIPTION_ID', 'LOC', 'RG', 'SRV', 'DB', 'ADMIN_OBJECT_ID', 'SQL_ADMIN_PASSWORD') { $required.Add($k) }
if ($chapters | Where-Object { $_ -in 5, 6, 8 }) { $required.Add('AI_RESOURCE') }
if (5 -in $chapters -and -not $NoGateway) { $required.Add('PUBLISHER_EMAIL') }
if (8 -in $chapters -and 'Tde' -notin $ExcludeTag) { $required.Add('TDE_VAULT_PREFIX') }
if (9 -in $chapters -and 'Geo' -notin $ExcludeTag) { $required.Add('GEO_SERVER') }
if (10 -in $chapters -and 'Sqlsim' -notin $ExcludeTag) { $required.Add('SQLSIM') }
$null = Import-BookTestEnvironment -Path $EnvFile -Require $required

foreach ($tool in 'az', 'dotnet') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool is required for the live tier." }
}
$null = Get-BookSqlCmd
if ((10 -in $chapters) -and 'Sqlsim' -notin $ExcludeTag) {
    if (-not $IsWindows) { throw 'Chapter 10 Demos 1 and 2 use sqlsim, which is Windows-only. Re-run with -ExcludeTag Sqlsim.' }
    if (-not (Test-Path -LiteralPath $env:SQLSIM)) { throw "SQLSIM does not exist: $env:SQLSIM" }
}

# The book's names, pointed at the test environment. Shell variables win over a
# reader's own ch04.env / ch05.env, so those files are never used for the run.
$env:WardGeneral__Server = "$($env:SRV).database.windows.net"
$env:WardGeneral__Database = $env:DB
# Set every ch04.env / ch05.env key explicitly, with the defaults the scripts
# would derive. load-env.ps1 fills only keys the shell leaves unset, so a key
# left unset here would be read from the tester's own file.
if ($env:AI_RESOURCE) {
    $env:Agent__Endpoint = "https://$($env:AI_RESOURCE).openai.azure.com/"
    if (-not $env:APIM_NAME) { $env:APIM_NAME = "$($env:AI_RESOURCE)-gateway" }
    if (-not $env:CS_RESOURCE) { $env:CS_RESOURCE = "$($env:AI_RESOURCE)-contentsafety" }
}
if (-not $env:AI_LOCATION) { $env:AI_LOCATION = $env:LOC }
if (-not $env:GATEWAY_LOCATION) { $env:GATEWAY_LOCATION = $env:AI_LOCATION }
if (-not $env:PUBLISHER_EMAIL) { $env:PUBLISHER_EMAIL = 'booktest@example.com' }
$env:TAGS = 'environment=sandbox application=ward-general-ehr criticality=low dataClassification=nonproduction booktest=true'
$env:BOOKTEST_EVIDENCE = $OutputDirectory
$env:BOOKTEST_NO_GATEWAY = if ($NoGateway) { '1' } else { '0' }
if ($env:TDE_VAULT_PREFIX) {
    $suffix = -join ((48..57) + (97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
    $prefix = ($env:TDE_VAULT_PREFIX -replace '[^a-zA-Z0-9-]', '').ToLowerInvariant()
    $env:BOOKTEST_TDE_VAULT = ($prefix.Substring(0, [Math]::Min($prefix.Length, 17)) + '-' + $suffix)
}

foreach ($file in 'ch04-first-app/ch04.env', 'ch05-ai-ready-sql/ch05.env') {
    $p = Join-Path $repo 'examples' $file
    if (Test-Path -LiteralPath $p) {
        Write-Host "Note: examples/$file exists. Its values are overridden for this run; the file is not changed." -ForegroundColor DarkYellow
    }
}

# --- Target safety --------------------------------------------------------------
$account = Invoke-BookAz account show
if (-not $account) { throw 'Not signed in to Azure. Run az login.' }
# The examples use the CLI's current subscription; put the tester's back afterwards.
$originalSubscription = $account.id
function Restore-Subscription {
    if ($originalSubscription -and $originalSubscription -ne $env:SUBSCRIPTION_ID) {
        & az account set --subscription $originalSubscription 2>$null
    }
}
& az account set --subscription $env:SUBSCRIPTION_ID
if ($LASTEXITCODE -ne 0) { throw "Cannot select subscription $($env:SUBSCRIPTION_ID)." }

$rg = Invoke-BookAz group show --name $env:RG
$rgOwned = Test-BookTestTag $rg
if ($rg -and -not $rgOwned) {
    Restore-Subscription
    throw "Resource group '$($env:RG)' exists in subscription $($env:SUBSCRIPTION_ID) and was not created by the test suite (no booktest=true tag). The live tier never touches it. Use a different subscription (recommended, so the book's names can be kept) or a different RG."
}
$environmentExists = [bool]$rg -and [bool](Invoke-BookAz sql db show --resource-group $env:RG --server $env:SRV --name $env:DB)
if (-not $environmentExists -and 2 -notin $chapters) {
    Restore-Subscription
    throw "No test environment exists yet. Include Chapter 2 (or run without -Chapter) to create it."
}

$plan = @(
    '',
    'Book test suite - LIVE tier plan',
    "  Subscription : $($env:SUBSCRIPTION_ID) ($($account.user.name))",
    "  Region       : $($env:LOC)",
    "  Environment  : $($env:RG) / $($env:SRV) / $($env:DB) $(if ($environmentExists) { '(exists, tagged booktest=true)' } else { '(will be created)' })",
    "  Chapters     : $($chapters -join ', ')",
    "  Excluded tags: $(if ($ExcludeTag) { $ExcludeTag -join ', ' } else { 'none' })",
    "  Chapter 5    : $(if ($NoGateway) { 'no API Management gateway' } else { 'with API Management (adds 30-45 min)' }); embeddings limit $($env:BOOKTEST_EMBEDDING_LIMIT ?? 2000) (0 = full corpus, 3-4 h)",
    "  Afterwards   : $(if ($KeepEnvironment) { 'KEEP the environment (it keeps billing)' } else { 'delete everything the suite created' })",
    "  Evidence     : $OutputDirectory",
    '',
    '  Billable: an 8-vCore Hyperscale database with one HA replica and a named replica,',
    '  scaled to 16 and 40 vCores in Chapter 10, plus a PITR copy, a geo-replica server,',
    '  Microsoft Foundry, API Management, Log Analytics, and a Key Vault. A full run takes',
    '  several hours. Check costs with examples/ch02-getting-started/estimate-cost.ps1.',
    ''
)
$plan | ForEach-Object { Write-Host $_ }
if (-not $AcceptCharges) {
    Restore-Subscription
    Write-Host 'PLAN ONLY. Nothing was created. Re-run with -AcceptCharges to run the live tier.' -ForegroundColor Yellow
    exit 0
}

# --- Run ------------------------------------------------------------------------------
$results = [Collections.Generic.List[object]]::new()
$liveFiles = Get-ChildItem (Join-Path $here 'live') -Filter '*.Tests.ps1' | Sort-Object Name
$chapterFiles = foreach ($n in $chapters) {
    $file = $liveFiles | Where-Object { $_.Name -like ('{0:D2}-*' -f $n) } | Select-Object -First 1
    if (-not $file) { Restore-Subscription; throw "No live tests for Chapter $n." }
    [pscustomobject]@{ Chapter = $n; File = $file }
}
try {
    foreach ($entry in $chapterFiles) {
        $n = $entry.Chapter
        $file = $entry.File
        Write-Host ''
        Write-Host "=== Chapter $n - $($file.Name)" -ForegroundColor Cyan
        $result = Invoke-BookPester -Path $file.FullName -Name ('live-ch{0:D2}' -f $n) -StopBlockOnFailure
        $results.Add($result)
        if ($n -eq 2 -and (Get-FailureCount $result) -gt 0) {
            Write-Host 'Chapter 2 failed; every later chapter depends on its database. Stopping.' -ForegroundColor Red
            break
        }
    }
}
finally {
    Write-Host ''
    Write-Host '=== Stopping local apps' -ForegroundColor Cyan
    foreach ($stop in @(
            @{ Script = 'examples/ch08-security/rls/stop-local-apps.ps1'; Name = 'teardown/stop-local-apps' },
            @{ Script = 'examples/ch04-first-app/shutdown.ps1'; Name = 'teardown/shutdown' })) {
        try { $null = Invoke-BookScript -Script $stop.Script -Arguments '-Confirm:$false' -Name $stop.Name -TimeoutMinutes 5 }
        catch { Write-Warning $_.Exception.Message }
    }

    if ($KeepEnvironment) {
        Write-Host "Keeping $($env:RG). It keeps billing; delete it with: az group delete --name $($env:RG)" -ForegroundColor Yellow
    }
    else {
        Write-Host '=== Teardown' -ForegroundColor Cyan
        $results.Add((Invoke-BookPester -Path (Join-Path $here 'live' 'teardown.Tests.ps1') -Name 'live-teardown'))
    }
    Restore-Subscription
}

$failed = Write-Summary $results.ToArray()
exit $(if ($failed) { 1 } else { 0 })
