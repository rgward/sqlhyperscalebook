#requires -Version 7.0
<#
    Ward General Hospital Digital Chart Application
    preflight-run.ps1 : check that the app can REACH ITS DATA before it starts.

    Everything here is about the path from this machine to Azure SQL. None of
    it is needed to compile the solution -- see preflight-build.ps1 for that.

    Checks:
      1. Azure sign-in   az installed, and `az login` done   (failure)
      2. Firewall        this client's IP is allowed through (delegated)
      3. Database        reachable, Chapter 2 schema + data  (failure)

    Why these are failures rather than warnings: the app authenticates with
    DefaultAzureCredential, which uses the same sign-in as the Azure CLI.
    Without it, Kestrel starts, the page renders -- and the first data load
    throws. The error surfaces as an application bug, pages away from its real
    cause. Catching it here is the whole point.

    run.ps1 calls this automatically. Exit code 0 = ready. 1 = a failure.

    With no arguments the server and database come from the same places the app
    itself reads them, highest first: the WardGeneral__Server / WardGeneral__Database
    environment variables, then src/WardGeneral.Web/appsettings.Development.json,
    then appsettings.json. Pass them explicitly to override.

    appsettings.json ships with an EMPTY server on purpose -- no live server name is
    ever the committed default. Supplying one is the reader's first job.

    Usage:
      ./preflight-run.ps1
      ./preflight-run.ps1 -SkipFirewall
      ./preflight-run.ps1 -Server <your-server> -Database <your-database>
#>
[CmdletBinding()]
param(
    [string]$Server,
    [string]$Database,
    [switch]$SkipFirewall
)

$root = $PSScriptRoot
$failures = 0
$warnings = 0

function Write-Check {
    param([ValidateSet('pass', 'warn', 'fail', 'skip')][string]$Result, [string]$Name, [string]$Detail)
    $mark, $color = switch ($Result) {
        'pass' { '  OK  ', 'Green' }
        'warn' { ' WARN ', 'Yellow' }
        'fail' { ' FAIL ', 'Red' }
        'skip' { ' SKIP ', 'DarkGray' }
    }
    Write-Host "[$mark] " -ForegroundColor $color -NoNewline
    Write-Host $Name -NoNewline
    if ($Detail) { Write-Host " - $Detail" -ForegroundColor DarkGray } else { Write-Host '' }
}

Write-Host "`nWard General - run pre-flight`n" -ForegroundColor Cyan

# One source of truth for where the app points: the same configuration chain the
# app itself reads, in the same order. Parameters override everything.
$webDir = Join-Path $root 'src' 'WardGeneral.Web'
if (-not $Server -or -not $Database) {
    function Read-Setting {
        param([string]$File, [string]$Name)
        $path = Join-Path $webDir $File
        if (-not (Test-Path $path)) { return $null }
        $value = (Get-Content $path -Raw | ConvertFrom-Json).WardGeneral.$Name
        if ([string]::IsNullOrWhiteSpace($value)) { return $null } else { return $value }
    }

    if (-not $Server) {
        $Server = $env:WardGeneral__Server ?? (Read-Setting 'appsettings.Development.json' 'Server') `
            ?? (Read-Setting 'appsettings.json' 'Server')
    }
    if (-not $Database) {
        $Database = $env:WardGeneral__Database ?? (Read-Setting 'appsettings.Development.json' 'Database') `
            ?? (Read-Setting 'appsettings.json' 'Database')
    }
}

if (-not $Server) {
    Write-Check fail 'Configuration' 'no server configured'
    Write-Host ''
    Write-Host '  Point the app at your Hyperscale database in any one of these:' -ForegroundColor Yellow
    Write-Host '    ./run.ps1 -Server <your-server>.database.windows.net' -ForegroundColor DarkGray
    Write-Host '    $env:WardGeneral__Server = ''<your-server>.database.windows.net''' -ForegroundColor DarkGray
    Write-Host '    src/WardGeneral.Web/appsettings.Development.json  (git-ignored)' -ForegroundColor DarkGray
    Write-Host ''
    exit 1
}

# -- 1. Azure sign-in -------------------------------------------------------
$signedIn = $false
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Check fail 'Azure CLI' 'not found on PATH - see https://aka.ms/installazurecli'
    $failures++
}
else {
    $acct = az account show -o json 2>$null | ConvertFrom-Json
    if (-not $acct) {
        Write-Check fail 'Azure sign-in' "not signed in - run 'az login'"
        $failures++
    }
    else {
        # Print what we found. A reader signed in to the wrong tenant sees a
        # permissions error later that looks nothing like the real cause.
        Write-Check pass 'Azure sign-in' "$($acct.user.name) / $($acct.name)"
        $signedIn = $true
    }
}

# -- 2. Firewall ------------------------------------------------------------
# Delegated to Chapter 2's script, which detects this client's public IP and
# PROMPTS before adding a single named rule (it never opens 0.0.0.0).
if ($SkipFirewall) {
    Write-Check skip 'Firewall' '-SkipFirewall'
}
elseif (-not $signedIn) {
    Write-Check skip 'Firewall' 'needs an Azure sign-in first'
}
else {
    $fwScript = Join-Path $root '..' 'ch02-getting-started' 'preflight-firewall.ps1'
    if (-not (Test-Path $fwScript)) {
        Write-Check warn 'Firewall' "Chapter 2 script not found at $fwScript"
        $warnings++
    }
    else {
        # Let its output through: this script can PROMPT to add a rule, and a
        # swallowed prompt looks like a hang.
        & $fwScript -Server (([string]$Server).Split('.')[0])
        switch ($LASTEXITCODE) {
            0 { Write-Check pass 'Firewall' 'this client is allowed through' }
            1 {
                Write-Check warn 'Firewall' 'declined or skipped - connections may fail'
                $warnings++
            }
            default {
                Write-Check warn 'Firewall' "check could not run (exit $LASTEXITCODE)"
                $warnings++
            }
        }
        $global:LASTEXITCODE = 0
    }
}

# -- 3. Database ------------------------------------------------------------
if (-not $signedIn) {
    Write-Check skip 'Database' 'needs an Azure sign-in first'
}
elseif (-not $Server -or -not $Database) {
    Write-Check fail 'Database' 'could not determine server/database - pass -Server and -Database'
    $failures++
}
else {
    # Microsoft.Data.SqlClient ships with the app, not with PowerShell. The
    # assembly at the root of the build output is a facade -- loading it gives
    # "not supported on this platform". The real implementation lives under
    # runtimes/<rid>/lib, so look there, in the build output and the NuGet cache.
    $rid = if ($IsWindows) { 'win' } else { 'unix' }
    $candidates = @()
    $candidates += Get-ChildItem -Path (Join-Path $root 'src') -Filter 'Microsoft.Data.SqlClient.dll' -Recurse -ErrorAction SilentlyContinue
    $candidates += Get-ChildItem -Path (Join-Path $HOME '.nuget' 'packages' 'microsoft.data.sqlclient') -Filter 'Microsoft.Data.SqlClient.dll' -Recurse -ErrorAction SilentlyContinue

    $driver = $candidates |
        Where-Object { $_.DirectoryName -match "[\\/]runtimes[\\/]$rid[\\/]lib[\\/]net" } |
        Sort-Object FullName -Descending |
        Select-Object -First 1

    if (-not $driver) {
        Write-Check warn 'Database' 'SQL client not found - build the app first, then re-run'
        $warnings++
    }
    else {
        try {
            # On Windows the client prefers a native SNI companion that the app
            # locates through deps.json at run time. PowerShell has no deps.json,
            # so use the fully managed networking stack instead. Must be set
            # before the connection type is first touched.
            if ($IsWindows) {
                [System.AppContext]::SetSwitch('Switch.Microsoft.Data.SqlClient.UseManagedNetworkingOnWindows', $true)
            }
            # Add-Type throws if some other copy of this assembly is already in
            # the process, so only load when the type is genuinely absent.
            if (-not ('Microsoft.Data.SqlClient.SqlConnection' -as [type])) {
                Add-Type -Path $driver.FullName -ErrorAction Stop
            }

            $token = az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv 2>$null
            if (-not $token) { throw 'could not acquire an Entra token for Azure SQL' }

            $conn = [Microsoft.Data.SqlClient.SqlConnection]::new(
                "Server=tcp:$Server,1433;Database=$Database;Encrypt=True;Connect Timeout=15")
            $conn.AccessToken = $token.Trim()
            $conn.Open()

            # Schema AND data. A reader who ran the Chapter 2 schema scripts but
            # skipped the seed gets a working app with empty screens, which is a
            # confusing place to land.
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = @"
SELECT CASE WHEN OBJECT_ID('clinical.Patient') IS NOT NULL
             AND OBJECT_ID('clinical.GetPatientChart') IS NOT NULL THEN 1 ELSE 0 END,
       CASE WHEN OBJECT_ID('clinical.Patient') IS NULL THEN -1
            ELSE (SELECT COUNT(*) FROM clinical.Patient) END
"@
            $r = $cmd.ExecuteReader()
            $null = $r.Read()
            $hasSchema = $r.GetInt32(0) -eq 1
            $patients = $r.GetInt32(1)
            $r.Close(); $conn.Close()

            if (-not $hasSchema) {
                Write-Check fail 'Database' 'connected, but the Chapter 2 schema is missing - run the Chapter 2 schema scripts'
                $failures++
            }
            elseif ($patients -le 0) {
                Write-Check fail 'Database' 'schema is there but no patients - run the Chapter 2 seed script'
                $failures++
            }
            else {
                Write-Check pass 'Database' "$Database on $Server - schema present, $patients patients"
            }
        }
        catch {
            Write-Check fail 'Database' $_.Exception.Message
            $failures++
        }
    }
}

Write-Host ''
if ($failures -gt 0) {
    Write-Host "Run pre-flight failed: $failures problem(s) to fix before the app will work.`n" -ForegroundColor Red
    exit 1
}
elseif ($warnings -gt 0) {
    Write-Host "Run pre-flight passed with $warnings warning(s).`n" -ForegroundColor Yellow
}
else {
    Write-Host "Run pre-flight passed.`n" -ForegroundColor Green
}
exit 0
