<#
.SYNOPSIS
    Build the Ward General app and start it with the Chapter 5 AI features
    already on -- the AI assistance card on the chart, and the Research page.

.DESCRIPTION
    Chapter 5's reader wants one thing: the app on screen with the AI working.
    This is that command. It builds, then starts the app with the AiAssistance
    feature flag set, and opens the browser.

    WHY THERE IS NO COPY OF THE APP IN THIS FOLDER
    ----------------------------------------------
    There is exactly one Ward General application, and it lives in
    examples/ch04-first-app. This script drives it from here.

    That is not filing tidiness, it is the chapter's argument. Chapter 5 moves
    the AI into the database -- the embeddings, the vector index, the search, the
    model call, the audit ledger are all objects in `wardgeneral`. The
    application does not change. Research.razor and the assistance card on
    Chart.razor were already compiled into the Chapter 4 build; they were sitting
    there greyed out, waiting for the SQL behind them to exist. Shipping a second
    copy of the app for the AI chapter would quietly claim the opposite -- that
    you need a new application to get AI -- which is the belief this chapter is
    trying to dislodge.

    So the only difference between "the Chapter 4 app" and "the Chapter 5 app" is
    one boolean, and this script sets it.

    The same holds later: Chapter 6 turns on AiAgent, Chapter 8 turns on
    RowLevelSecurity, both against this same build. If you ever find yourself
    about to copy src/ into a chapter folder, that is the signal something has
    been misunderstood.

    HOW THE FLAG TRAVELS
    --------------------
    restart.ps1 sets the environment variable Features__AiAssistance, which
    ASP.NET Core reads as the config path Features:AiAssistance, and which
    outranks appsettings.json. The flags bind once, as IOptions<FeatureFlags>, at
    startup -- so this has to be a real process restart. A page refresh will not
    do it, and neither will run.ps1, which sees the old process still holding
    7170 and just opens a browser at it.

    WHAT HAS TO BE TRUE FIRST
    -------------------------
    Run deploy-ai.ps1 in this folder first. The panels degrade gracefully rather
    than crashing -- the data layer reads the backing columns column-tolerantly --
    so if the SQL is missing you get an empty card rather than an error page,
    which is a slower way to discover the same problem.

    In particular the corpus has to be embedded. Assistance and Research both run
    VECTOR_SEARCH; against an empty clinical.ClinicalNoteEmbeddings they return
    nothing and look broken. Check with verify-embeddings.sql.

.PARAMETER Configuration
    Debug (default) or Release. Passed to build.ps1.

.PARAMETER Clean
    Delete bin/obj/publish before building. Passed to build.ps1.

.PARAMETER SkipBuild
    Go straight to starting the app. The build is already current.

.PARAMETER Server
    Override the logical server. Exported as WardGeneral__Server so the app and
    its pre-flight read the same value. Omit and the app uses its own layered
    configuration.

.PARAMETER Database
    Override the database name. Exported as WardGeneral__Database.

.PARAMETER NoBrowser
    Start the app without opening a browser.

.PARAMETER SkipPreflight
    Skip the sign-in, firewall and database checks in build and run alike.

.EXAMPLE
    .\run-ai-app.ps1
    Build, start with AI assistance on, open the browser.

.EXAMPLE
    .\run-ai-app.ps1 -SkipBuild
    The app is already built -- just restart it with the flag on.

.EXAMPLE
    .\run-ai-app.ps1 -Clean -Configuration Release
    Full rebuild, then start.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string] $Configuration = 'Debug',
    [string] $Server,
    [string] $Database,
    [switch] $Clean,
    [switch] $SkipBuild,
    [switch] $NoBrowser,
    [switch] $SkipPreflight
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

# ch05.env carries WardGeneral__Server / __Database for the app (see the
# template), so load it when present. A value already in the shell wins, and an
# explicit -Server/-Database still overrides both. No values are required here:
# the app's own pre-flight reports a missing server with every way to fix it.
if (Test-Path (Join-Path $here 'ch05.env')) {
    & (Join-Path $here 'load-env.ps1') -Require @() -Quiet
}

# The one app, resolved relative to this folder so it works the same in this repo
# and in the reader-facing companion repo -- publish-examples.ps1 mirrors both
# chapters into the same layout, so this relative hop is stable on both sides.
$appRoot = (Resolve-Path (Join-Path $here '..' 'ch04-first-app') -ErrorAction SilentlyContinue)?.Path

if (-not $appRoot) {
    throw @"
The Ward General app was not found at examples/ch04-first-app.

Chapter 5 does not ship its own copy of the application -- it drives the one
Chapter 4 builds. Clone or download the whole examples/ folder, not this chapter
on its own.
"@
}

$build = Join-Path $appRoot 'build.ps1'
$restart = Join-Path $appRoot 'restart.ps1'
foreach ($s in @($build, $restart)) {
    if (-not (Test-Path $s)) { throw "Expected script not found: $s" }
}

Write-Host '=============================================' -ForegroundColor Cyan
Write-Host ' Chapter 5 : the app, with AI assistance on'   -ForegroundColor Cyan
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host "  app      : $appRoot" -ForegroundColor Gray
Write-Host '  features : AiAssistance (AI card on the chart + the Research page)' -ForegroundColor Gray
Write-Host ''

# ------------------------------------------------------------------- build
if ($SkipBuild) {
    Write-Host '--- Build skipped (-SkipBuild).' -ForegroundColor DarkGray
}
else {
    Write-Host '--- Building...' -ForegroundColor Cyan

    $buildArgs = @{ Configuration = $Configuration }
    if ($Clean) { $buildArgs['Clean'] = $true }
    if ($SkipPreflight) { $buildArgs['SkipPreflight'] = $true }

    & $build @buildArgs
    if ($LASTEXITCODE -ne 0) { throw "Build failed (exit $LASTEXITCODE)." }
}

# ------------------------------------------------------------------- start
# restart.ps1 rather than run.ps1, deliberately. run.ps1 declines to start a
# second instance and just opens a browser at whatever is already on 7170, which
# would hand back the old process with the flag still off -- and the flag would
# look broken when it was never read. restart.ps1 from cold is fine: shutdown.ps1
# reports "nothing to stop" and carries on.
Write-Host ''
Write-Host '--- Starting with Features__AiAssistance = true...' -ForegroundColor Cyan

$restartArgs = @{ Enable = @('AiAssistance') }
if ($Server) { $restartArgs['Server'] = $Server }
if ($Database) { $restartArgs['Database'] = $Database }
if ($NoBrowser) { $restartArgs['NoBrowser'] = $true }
if ($SkipPreflight) { $restartArgs['SkipPreflight'] = $true }

& $restart @restartArgs

Write-Host ''
Write-Host ' The two Chapter 5 surfaces:' -ForegroundColor Green
Write-Host '   /chart/{EncounterId}  the AI assistance card, from clinical.GenerateClinicalAssistance' -ForegroundColor White
Write-Host '   /research             vector search, from clinical.SearchSimilarNotes on the named replica' -ForegroundColor White
Write-Host ''
Write-Host ' Empty results usually mean the corpus is not embedded yet. Run' -ForegroundColor Gray
Write-Host ' verify-embeddings.sql -- if MISSING is large, re-run step 4 of' -ForegroundColor Gray
Write-Host ' 06-ai-embeddings.sql. It resumes rather than starting over.' -ForegroundColor Gray
Write-Host ''
