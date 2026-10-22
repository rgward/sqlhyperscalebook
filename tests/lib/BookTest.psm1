#requires -Version 7.0
<#
.SYNOPSIS
    Shared helpers for the book's automated test suite.

.DESCRIPTION
    Offline tests run a repository script in a separate pwsh process with:
      - fake native `az` and `sqlcmd` executables (New-RecordingAz,
        New-FakeSqlCmd) first on PATH, so the real Azure CLI is never reached;
        AZURE_CONFIG_DIR also points at an empty folder,
      - explicit environment variables, which win over the reader's own
        ch04.env / ch05.env, so a reader's real configuration is never used.
    The child's exit code matches what a reader would see from pwsh -File.

    Live tests use Import-BookTestEnvironment to load tests/test.env and
    Invoke-BookScript to run a script with real tools, capturing output to the
    run's evidence folder.
#>

Set-StrictMode -Version Latest

$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$script:CacheRoot = Join-Path $script:RepoRoot 'tests' '.cache'

function Get-BookRepoRoot { $script:RepoRoot }

function Get-BookPath {
    <# Resolve a repository-relative path, for example 'examples/ch04-first-app/run.ps1'. #>
    param([Parameter(Mandatory)] [string] $RelativePath)
    Join-Path $script:RepoRoot ($RelativePath -replace '[\\/]', [IO.Path]::DirectorySeparatorChar)
}

function New-TestScratch {
    <# A unique scratch folder under the OS temp directory. #>
    param([string] $Prefix = 'booktest')
    $path = Join-Path ([IO.Path]::GetTempPath()) ("{0}-{1}" -f $Prefix, [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    $path
}

function ConvertTo-EnvLines {
    param([hashtable] $Environment)
    foreach ($key in $Environment.Keys) {
        $value = $Environment[$key]
        if ($null -eq $value) { "Remove-Item Env:$key -ErrorAction SilentlyContinue" }
        else { "`$env:$key = '$(([string]$value).Replace("'", "''"))'" }
    }
}

function New-RunnerScript {
    # The exit code matches `pwsh -File <script>`: 0 on success (even if a
    # native command earlier in the script failed), N after `exit N`, 1 after
    # an uncaught error. Thrown messages are echoed unwrapped as BOOKTEST_THREW.
    param([string] $Path, [string[]] $EnvLines, [string] $WorkingDirectory, [string] $Prelude, [string] $ScriptPath, [string] $Arguments)
    @"
`$ErrorActionPreference = 'Continue'
$($EnvLines -join [Environment]::NewLine)
Set-Location -LiteralPath '$($WorkingDirectory.Replace("'", "''"))'
$Prelude
`$global:LASTEXITCODE = 0
try {
    & '$($ScriptPath.Replace("'", "''"))' $Arguments
    `$ok = `$?
}
catch {
    [Console]::Out.WriteLine('BOOKTEST_THREW=' + (`$_.Exception.Message -replace '\r?\n', ' '))
    exit 1
}
exit `$(if (`$ok) { 0 } elseif (`$global:LASTEXITCODE) { `$global:LASTEXITCODE } else { 1 })
"@ | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
}

function ConvertTo-RunResult {
    param([string[]] $Lines, [int] $ProcessExitCode = 1, [string] $LogPath = $null)
    $threwLine = $Lines | Where-Object { $_ -like 'BOOKTEST_THREW=*' } | Select-Object -Last 1
    $clean = @($Lines | Where-Object { $_ -notlike 'BOOKTEST_*' })
    $threw = if ($threwLine) { $threwLine -replace '^BOOKTEST_THREW=', '' } else { $null }
    [pscustomobject]@{
        Output   = $clean
        Text     = (@($clean) + @($threw | Where-Object { $_ })) -join "`n"
        ExitCode = $ProcessExitCode
        Threw    = $threw
        LogPath  = $LogPath
    }
}

function Invoke-IsolatedScript {
    <#
    .SYNOPSIS
        Offline tier: run a repository script in a child pwsh with mocks and
        explicit environment variables. Never reaches Azure.

    .PARAMETER Script
        Repository-relative or absolute path to the script.
    .PARAMETER Arguments
        Text appended after the script path, for example "-Execute -Server s".
    .PARAMETER Prelude
        PowerShell run before the script, for example a global function that
        overrides a cmdlet such as Invoke-RestMethod.
    .PARAMETER Environment
        Environment variables for the child. A $null value removes the variable.

    .OUTPUTS
        [pscustomobject] Output (string[]), Text, ExitCode, Threw.
    #>
    param(
        [Parameter(Mandatory)] [string] $Script,
        [string] $Arguments = '',
        [string] $Prelude = '',
        [hashtable] $Environment = @{},
        [string] $WorkingDirectory = $script:RepoRoot,
        [int] $TimeoutSeconds = 300
    )

    $scriptPath = if ([IO.Path]::IsPathRooted($Script)) { $Script } else { Get-BookPath $Script }
    if (-not (Test-Path -LiteralPath $scriptPath)) { throw "Script not found: $scriptPath" }

    $scratch = New-TestScratch 'isolated'
    $azConfig = Join-Path $scratch 'azure-config'
    New-Item -ItemType Directory -Path $azConfig -Force | Out-Null
    $envLines = @("`$env:AZURE_CONFIG_DIR = '$($azConfig.Replace("'", "''"))'") + @(ConvertTo-EnvLines $Environment)

    $runner = Join-Path $scratch 'run.ps1'
    New-RunnerScript -Path $runner -EnvLines $envLines -WorkingDirectory $WorkingDirectory `
        -Prelude $Prelude -ScriptPath $scriptPath -Arguments $Arguments

    $psi = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
    foreach ($a in @('-NoProfile', '-NonInteractive', '-File', $runner)) { $psi.ArgumentList.Add($a) }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = $WorkingDirectory
    $process = [Diagnostics.Process]::Start($psi)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $process.Kill($true)
        throw "Timed out after $TimeoutSeconds s: $scriptPath $Arguments"
    }
    $text = $stdoutTask.Result + $stderrTask.Result
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    ConvertTo-RunResult -Lines @($text -split '\r?\n') -ProcessExitCode $process.ExitCode
}

function New-FakeTool {
    <#
    .SYNOPSIS
        Build (once, cached in tests/.cache) a small native executable that
        stands in for a tool such as sqlcmd or sqlsim.

    .DESCRIPTION
        Some scripts launch tools as real processes (System.Diagnostics.Process),
        so a PowerShell function can't stand in for them. This compiles a tiny
        .NET console program from C# source and returns the executable's path.
        Requires the .NET SDK.
    #>
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Source
    )
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Name + $Source))).Substring(0, 12)
    $dir = Join-Path $script:CacheRoot "fake-$Name-$hash"
    $exe = Join-Path $dir 'bin' ($(if ($IsWindows) { "$Name.exe" } else { $Name }))
    if (Test-Path -LiteralPath $exe) { return $exe }

    $src = Join-Path $dir 'src'
    New-Item -ItemType Directory -Path $src -Force | Out-Null
    @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <AssemblyName>$Name</AssemblyName>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>
</Project>
"@ | Set-Content -LiteralPath (Join-Path $src "$Name.csproj") -Encoding utf8NoBOM
    $Source | Set-Content -LiteralPath (Join-Path $src 'Program.cs') -Encoding utf8NoBOM
    $out = & dotnet publish (Join-Path $src "$Name.csproj") -c Release -o (Join-Path $dir 'bin') --nologo -v q 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $exe)) {
        throw "Could not build fake tool '$Name': $($out -join ' ')"
    }
    $exe
}


$script:FakeAzSource = @'
using System.Text.Json;
using System.Text.RegularExpressions;

// Offline stand-in for the Azure CLI. Logs each call to BOOKTEST_AZ_LOG and
// answers from the [pattern, reply] rules in BOOKTEST_AZ_RULES; first match wins.
var line = string.Join(' ', args);
var log = Environment.GetEnvironmentVariable("BOOKTEST_AZ_LOG");
if (!string.IsNullOrEmpty(log)) File.AppendAllText(log, line + Environment.NewLine);
var rulesPath = Environment.GetEnvironmentVariable("BOOKTEST_AZ_RULES");
if (string.IsNullOrEmpty(rulesPath) || !File.Exists(rulesPath))
{
    Console.Error.WriteLine("fake az: BOOKTEST_AZ_RULES is not set; refusing to answer.");
    return 2;
}
var rules = JsonSerializer.Deserialize<string[][]>(File.ReadAllText(rulesPath)) ?? [];
foreach (var rule in rules)
{
    if (!Regex.IsMatch(line, rule[0])) continue;
    var reply = rule[1];
    var code = 0;
    var exit = Regex.Match(reply, @"^EXIT:(\d+)\|?(.*)$", RegexOptions.Singleline);
    if (exit.Success) { code = int.Parse(exit.Groups[1].Value); reply = exit.Groups[2].Value; }
    if (reply.Length > 0) foreach (var l in reply.Split("||")) Console.WriteLine(l);
    if (code != 0) Console.Error.WriteLine($"ERROR: fake az exit {code}");
    return code;
}
return 0;
'@

function New-RecordingAz {
    <#
    .SYNOPSIS
        Environment for a fake native `az` that logs every call and answers
        read commands with plausible JSON. Pass .Environment to
        Invoke-IsolatedScript, then call Get-AzMutations on .LogPath.

    .DESCRIPTION
        The fake is a real executable placed first on PATH, so scripts see the
        same native-command behavior ($LASTEXITCODE, 2>$null,
        $PSNativeCommandUseErrorActionPreference) as with the Azure CLI.
        $Responses maps a regex (matched against the space-joined arguments)
        to the reply; the first match wins, then built-in defaults apply.
        Separate output lines with '||'. Prefix a reply with 'EXIT:n|' to make
        the call fail with exit code n (the Azure CLI uses 3 for "not found").
    #>
    param(
        [System.Collections.IDictionary] $Responses = [ordered]@{}
    )
    $exe = New-FakeTool -Name 'az' -Source $script:FakeAzSource
    $scratch = New-TestScratch 'az'
    $db = '{"id":"/subscriptions/0/resourceGroups/rg-collierhealth/providers/Microsoft.Sql/servers/collierhealth-test/databases/wardgeneral","name":"wardgeneral","status":"Online","edition":"Hyperscale","serviceObjective":"HS_Gen5_8","currentServiceObjectiveName":"HS_Gen5_8","capacity":8,"family":"Gen5","location":"westus3","zoneRedundant":true,"sourceDatabaseId":null,"secondaryType":null,"earliestRestoreDate":"2026-01-01T00:00:00Z"}'
    $rules = [Collections.Generic.List[object]]::new()
    foreach ($k in $Responses.Keys) { $rules.Add(@([string]$k, [string]$Responses[$k])) }
    foreach ($default in @(
            @('^account show.*tsv', 'booktest-sub'),
            @('^account show', '{"id":"00000000-0000-0000-0000-000000000000","name":"booktest","tenantId":"t","user":{"name":"tester@example.com"}}'),
            @('^account get-access-token', 'fake-token'),
            @('^group exists', 'true'),
            @('^sql db show', $db),
            @('^sql db (list|replica list-links)', '[]'),
            @('(^| )(create|update|delete|set|assign|purge|failover|restore|copy)( |$)', '{}'),
            @('^rest .*--method (post|put|patch|delete)', '{}'),
            @('.*', '[]')
        )) { $rules.Add($default) }
    $rulesPath = Join-Path $scratch 'rules.json'
    ConvertTo-Json -InputObject $rules.ToArray() -Depth 3 | Set-Content -LiteralPath $rulesPath -Encoding utf8NoBOM
    $logPath = Join-Path $scratch 'az.log'
    [pscustomobject]@{
        LogPath     = $logPath
        Environment = @{
            PATH              = (Split-Path $exe) + [IO.Path]::PathSeparator + $env:PATH
            BOOKTEST_AZ_LOG   = $logPath
            BOOKTEST_AZ_RULES = $rulesPath
        }
    }
}

$script:FakeSqlCmdSource = @'
// Offline stand-in for the go-based sqlcmd. Logs each call to
// BOOKTEST_SQLCMD_LOG, prints BOOKTEST_SQLCMD_OUTPUT (a file), and exits with
// BOOKTEST_SQLCMD_EXIT. --version answers like the new sqlcmd.
var log = Environment.GetEnvironmentVariable("BOOKTEST_SQLCMD_LOG");
if (!string.IsNullOrEmpty(log)) File.AppendAllText(log, string.Join(' ', args) + Environment.NewLine);
if (args.Contains("--version")) { Console.WriteLine("sqlcmd: 1.8.2"); return 0; }
var output = Environment.GetEnvironmentVariable("BOOKTEST_SQLCMD_OUTPUT");
if (!string.IsNullOrEmpty(output) && File.Exists(output)) Console.Write(File.ReadAllText(output));
return int.TryParse(Environment.GetEnvironmentVariable("BOOKTEST_SQLCMD_EXIT"), out var code) ? code : 0;
'@

function New-FakeSqlCmd {
    <#
    .SYNOPSIS
        Environment for a fake go-sqlcmd: SQLCMD points at it. Set
        $Output to the text it prints; read the calls from .LogPath.
    #>
    param([string] $Output = '', [int] $ExitCode = 0)
    $exe = New-FakeTool -Name 'sqlcmd' -Source $script:FakeSqlCmdSource
    $scratch = New-TestScratch 'sqlcmd'
    $outputPath = Join-Path $scratch 'output.txt'
    $Output | Set-Content -LiteralPath $outputPath -Encoding utf8NoBOM
    $logPath = Join-Path $scratch 'sqlcmd.log'
    [pscustomobject]@{
        Path        = $exe
        LogPath     = $logPath
        Environment = @{
            SQLCMD                 = $exe
            BOOKTEST_SQLCMD_LOG    = $logPath
            BOOKTEST_SQLCMD_OUTPUT = $outputPath
            BOOKTEST_SQLCMD_EXIT   = [string]$ExitCode
        }
    }
}

function Get-AzMutations {
    <# Lines from a New-RecordingAz log that would change Azure. #>
    param([Parameter(Mandatory)] [string] $LogPath)
    if (-not (Test-Path -LiteralPath $LogPath)) { return @() }
    @(Get-Content -LiteralPath $LogPath | Where-Object {
        $_ -match '^(\S+ )+(create|update|delete|delete-link|set|assign|purge|failover|restore|copy|start|stop|add|remove)( |$)' -or
        $_ -match '^rest .*--method (post|put|patch|delete)'
    } | Where-Object { $_ -notmatch '^account set' })
}

function Get-ScriptAst {
    param([Parameter(Mandatory)] [string] $Path)
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $Path).Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "Parse errors in ${Path}: $($errors[0].Message)" }
    $ast
}

function Import-BookTestEnvironment {
    <#
    .SYNOPSIS
        Load tests/test.env (KEY=VALUE) into the current process environment.
        Values still in <angle brackets> count as unset.
    #>
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string[]] $Require = @()
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Test environment file not found: $Path. Copy tests/test.env.template to tests/test.env and fill it in."
    }
    $loaded = [ordered]@{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        $i = $t.IndexOf('=')
        if ($i -lt 1) { continue }
        $key = $t.Substring(0, $i).Trim()
        $value = $t.Substring($i + 1).Trim()
        if ($value.Length -ge 2 -and (($value[0] -eq '"' -and $value[-1] -eq '"') -or ($value[0] -eq "'" -and $value[-1] -eq "'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        if (-not $value -or $value -match '<[^>]*>') { continue }
        Set-Item -Path "env:$key" -Value $value
        $loaded[$key] = $value
    }
    $missing = @($Require | Where-Object { -not [Environment]::GetEnvironmentVariable($_) })
    if ($missing.Count) { throw "$(Split-Path $Path -Leaf) is missing: $($missing -join ', ')" }
    $loaded
}

# ---------------------------------------------------------------------------
# Live tier
# ---------------------------------------------------------------------------

function Get-BookEvidencePath {
    <# Path for a named artifact (for example 'ch02/provision.log') in the run's evidence folder. #>
    param([Parameter(Mandatory)] [string] $Name)
    $evidence = $env:BOOKTEST_EVIDENCE
    if (-not $evidence) { throw 'BOOKTEST_EVIDENCE is not set; run the live tier through tests/Invoke-BookTests.ps1.' }
    $path = Join-Path $evidence ($Name -replace '[\\/]', [IO.Path]::DirectorySeparatorChar)
    New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
    $path
}

function Get-BookLiveContext {
    <# The live environment, read from the variables Invoke-BookTests.ps1 exported. #>
    $ai = $env:AI_RESOURCE
    [pscustomobject]@{
        SubscriptionId = $env:SUBSCRIPTION_ID
        Location       = $env:LOC
        ResourceGroup  = $env:RG
        Server         = $env:SRV
        Fqdn           = "$($env:SRV).database.windows.net"
        Database       = $env:DB
        NamedReplica   = $env:NAMED_REPLICA ?? 'wardgeneral-research'
        AiResource     = $ai
        Apim           = if ($env:APIM_NAME) { $env:APIM_NAME } elseif ($ai) { "$ai-gateway" } else { $null }
        NoGateway      = $env:BOOKTEST_NO_GATEWAY -eq '1'
        EmbeddingLimit = [int]($env:BOOKTEST_EMBEDDING_LIMIT ?? 2000)
        GrowthSeconds  = [int]($env:BOOKTEST_GROWTH_SECONDS ?? 300)
        TdeVault       = $env:BOOKTEST_TDE_VAULT
        GeoServer      = $env:GEO_SERVER
        GeoLocation    = $env:GEO_LOCATION
        Sqlsim         = $env:SQLSIM
        AppUrl         = 'https://localhost:7170'
    }
}

function Start-ChildPwsh {
    param([string] $Runner, [string] $LogPath)
    $pwsh = (Get-Process -Id $PID).Path
    $start = @{
        FilePath               = $pwsh
        ArgumentList           = "-NoProfile -NonInteractive -File `"$Runner`""
        RedirectStandardOutput = $LogPath
        RedirectStandardError  = "$LogPath.stderr"
        PassThru               = $true
        NoNewWindow            = $true
    }
    $process = Start-Process @start
    $null = $process.Handle   # keeps ExitCode readable after exit
    $process
}

function Read-ChildLog {
    param([string] $LogPath)
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($p in @($LogPath, "$LogPath.stderr")) {
        if (Test-Path -LiteralPath $p) { foreach ($l in Get-Content -LiteralPath $p) { $lines.Add($l) } }
    }
    , $lines.ToArray()
}

function Invoke-BookScript {
    <#
    .SYNOPSIS
        Live tier: run a repository script with real tools in a child pwsh and
        keep everything it printed in the run's evidence folder. Tail the log
        while it runs: Get-Content <log> -Wait.

    .OUTPUTS
        [pscustomobject] Output, Text, ExitCode, Threw, LogPath.
    #>
    param(
        [Parameter(Mandatory)] [string] $Script,
        [string] $Arguments = '',
        [Parameter(Mandatory)] [string] $Name,
        [hashtable] $Environment = @{},
        [string] $WorkingDirectory = $script:RepoRoot,
        [int] $TimeoutMinutes = 60
    )
    $scriptPath = if ([IO.Path]::IsPathRooted($Script)) { $Script } else { Get-BookPath $Script }
    $log = Get-BookEvidencePath "$Name.log"
    $runner = "$log.runner.ps1"
    New-RunnerScript -Path $runner -EnvLines @(ConvertTo-EnvLines $Environment) -WorkingDirectory $WorkingDirectory `
        -Prelude '' -ScriptPath $scriptPath -Arguments $Arguments

    Write-Host "      > $Name  ($log)" -ForegroundColor DarkGray
    $process = Start-ChildPwsh -Runner $runner -LogPath $log
    if (-not $process.WaitForExit($TimeoutMinutes * 60 * 1000)) {
        $process.Kill($true)
        throw "Timed out after $TimeoutMinutes min: $Name. See $log"
    }
    $process.WaitForExit()
    Remove-Item -LiteralPath $runner -ErrorAction SilentlyContinue
    ConvertTo-RunResult -Lines (Read-ChildLog $log) -ProcessExitCode $process.ExitCode -LogPath $log
}

function Start-BookBackground {
    <#
    .SYNOPSIS
        Start a script that holds its terminal (run-dab.ps1, restart.ps1, ...)
        as a background process. Stop it with Stop-BookBackground.
    #>
    param(
        [Parameter(Mandatory)] [string] $Script,
        [string] $Arguments = '',
        [Parameter(Mandatory)] [string] $Name,
        [hashtable] $Environment = @{}
    )
    $scriptPath = if ([IO.Path]::IsPathRooted($Script)) { $Script } else { Get-BookPath $Script }
    $log = Get-BookEvidencePath "$Name.log"
    $runner = "$log.runner.ps1"
    New-RunnerScript -Path $runner -EnvLines @(ConvertTo-EnvLines $Environment) -WorkingDirectory $script:RepoRoot `
        -Prelude '' -ScriptPath $scriptPath -Arguments $Arguments
    Write-Host "      > $Name (background)  ($log)" -ForegroundColor DarkGray
    $process = Start-ChildPwsh -Runner $runner -LogPath $log
    $process | Add-Member -NotePropertyName BookLog -NotePropertyValue $log -PassThru
}

function Stop-BookBackground {
    param([Parameter(ValueFromPipeline)] $Process)
    process {
        if ($Process -and -not $Process.HasExited) {
            try { $Process.Kill($true) } catch { Write-Verbose $_.Exception.Message }
        }
    }
}

function Wait-BookBackground {
    <# Wait for a Start-BookBackground script that ends on its own; return its run result. #>
    param([Parameter(Mandatory)] $Process, [int] $TimeoutMinutes = 30)
    if (-not $Process.WaitForExit($TimeoutMinutes * 60 * 1000)) {
        $Process.Kill($true)
        throw "Timed out after $TimeoutMinutes min. See $($Process.BookLog)"
    }
    $Process.WaitForExit()
    ConvertTo-RunResult -Lines (Read-ChildLog $Process.BookLog) -ProcessExitCode $Process.ExitCode -LogPath $Process.BookLog
}

function Get-BookSqlCmd {
    <# The go-based sqlcmd, found the same way the repository scripts find it. #>
    $candidates = @(
        $env:SQLCMD,
        $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs\sqlcmd\sqlcmd.exe' }),
        $(if ($IsWindows) { 'C:\Program Files\SqlCmd\sqlcmd.exe' }),
        (Get-Command sqlcmd -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
    )
    $found = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if (-not $found) { throw 'The new sqlcmd was not found. Install it with: winget install --id Microsoft.Sqlcmd' }
    $found
}

function Invoke-BookSql {
    <#
    .SYNOPSIS
        Live tier: run a .sql file or a query with sqlcmd and Entra
        authentication, exactly as a reader does, and log the output.
    #>
    param(
        [string] $File,
        [string] $Query,
        [string] $Database,
        [Parameter(Mandatory)] [string] $Name,
        [string[]] $ExtraArguments = @(),
        [switch] $AllowFailure,
        [int] $TimeoutMinutes = 60
    )
    $ctx = Get-BookLiveContext
    if (-not $Database) { $Database = $ctx.Database }
    $log = Get-BookEvidencePath "$Name.log"
    $arguments = @('-S', $ctx.Fqdn, '-d', $Database, '--authentication-method', 'ActiveDirectoryDefault', '-b') + $ExtraArguments
    if ($File) {
        $path = if ([IO.Path]::IsPathRooted($File)) { $File } else { Get-BookPath $File }
        $arguments += @('-i', $path)
    }
    elseif ($Query) { $arguments += @('-Q', $Query) }
    else { throw 'Pass -File or -Query.' }

    Write-Host "      > sqlcmd $Name  ($log)" -ForegroundColor DarkGray
    $psi = [Diagnostics.ProcessStartInfo]::new((Get-BookSqlCmd))
    foreach ($a in $arguments) { $psi.ArgumentList.Add($a) }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $process = [Diagnostics.Process]::Start($psi)
    $out = $process.StandardOutput.ReadToEndAsync()
    $err = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutMinutes * 60 * 1000)) {
        $process.Kill($true)
        throw "Timed out after $TimeoutMinutes min: sqlcmd $Name. See $log"
    }
    $text = $out.Result + $err.Result
    $text | Set-Content -LiteralPath $log -Encoding utf8NoBOM
    $result = [pscustomobject]@{
        Output   = @($text -split '\r?\n')
        Text     = $text
        ExitCode = $process.ExitCode
        LogPath  = $log
    }
    if ($result.ExitCode -ne 0 -and -not $AllowFailure) {
        $tail = ($result.Output | Select-Object -Last 15) -join "`n"
        throw "sqlcmd $Name failed (exit $($result.ExitCode)). See $log`n$tail"
    }
    $result
}

function Get-BookScalar {
    <# First value returned by a single-column query. #>
    param([Parameter(Mandatory)] [string] $Query, [string] $Database, [Parameter(Mandatory)] [string] $Name)
    $r = Invoke-BookSql -Query "SET NOCOUNT ON; $Query" -Database $Database -Name $Name -ExtraArguments @('-h', '-1', '-W')
    ($r.Output | Where-Object { $_.Trim() } | Select-Object -First 1)?.Trim()
}

function Copy-BookSql {
    <#
    .SYNOPSIS
        Copy a repository .sql file into the evidence folder with the reader's
        placeholder replacements applied. The repository file is never edited.
        Throws if any search text is missing, so a renamed placeholder fails
        loudly instead of silently running the unedited script.
    #>
    param(
        [Parameter(Mandatory)] [string] $File,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Replace,
        [Parameter(Mandatory)] [string] $Name
    )
    $source = if ([IO.Path]::IsPathRooted($File)) { $File } else { Get-BookPath $File }
    $text = Get-Content -LiteralPath $source -Raw
    foreach ($key in $Replace.Keys) {
        if (-not $text.Contains($key)) { throw "Copy-BookSql: '$key' not found in $File" }
        $text = $text.Replace($key, [string]$Replace[$key])
    }
    $target = Get-BookEvidencePath $Name
    $text | Set-Content -LiteralPath $target -Encoding utf8NoBOM
    $target
}

function Get-BookValue {
    <# The value of the last 'Key=Value' line in script output. #>
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Text, [Parameter(Mandatory)] [string] $Key)
    $m = [regex]::Matches($Text, "(?m)^\s*$([regex]::Escape($Key))=(.*)$")
    if ($m.Count) { $m[$m.Count - 1].Groups[1].Value.Trim() } else { $null }
}

function Wait-BookCondition {
    <#
    .SYNOPSIS
        Poll until the script block returns a truthy value; return that value.
        Used for asynchronous delivery (audit rows, AzureSQLErrors, endpoints).
    #>
    param(
        [Parameter(Mandatory)] [scriptblock] $Condition,
        [Parameter(Mandatory)] [string] $Because,
        [int] $TimeoutSeconds = 600,
        [int] $IntervalSeconds = 15
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $value = & $Condition
        if ($value) { return $value }
        Start-Sleep -Seconds $IntervalSeconds
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Timed out after $TimeoutSeconds s waiting for: $Because"
}

function Get-BookHttp {
    <# GET a local app URL (self-signed dev certificate); $null when it does not answer. #>
    param([Parameter(Mandatory)] [string] $Url, [int] $TimeoutSeconds = 30)
    try { Invoke-WebRequest -Uri $Url -SkipCertificateCheck -TimeoutSec $TimeoutSeconds -ErrorAction Stop }
    catch { $null }
}

function Get-BookState {
    param([Parameter(Mandatory)] [string] $Key)
    $path = Get-BookEvidencePath 'state.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $state = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
    $state[$Key]
}

function Set-BookState {
    param([Parameter(Mandatory)] [string] $Key, $Value)
    $path = Get-BookEvidencePath 'state.json'
    $state = if (Test-Path -LiteralPath $path) { Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable } else { @{} }
    $state[$Key] = $Value
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding utf8NoBOM
}

function Invoke-BookAz {
    <# az with JSON output parsed; $null when the command fails (for example, not found). #>
    $raw = & az @args -o json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return $null }
    ($raw -join "`n") | ConvertFrom-Json
}

function Test-BookTestTag {
    <# True when an Azure resource carries the suite's booktest=true tag. #>
    param($Resource)
    $Resource -and $Resource.PSObject.Properties['tags'] -and $Resource.tags -and
        $Resource.tags.PSObject.Properties['booktest'] -and $Resource.tags.booktest -eq 'true'
}

function Assert-BookDatabase {
    <# Throws unless the test database exists (chapters after 2 need it). #>
    $ctx = Get-BookLiveContext
    $db = Invoke-BookAz sql db show --resource-group $ctx.ResourceGroup --server $ctx.Server --name $ctx.Database
    if (-not $db) {
        throw "Database $($ctx.Server)/$($ctx.Database) does not exist. Run Chapter 2 first (-Chapter 2) or include it in this run."
    }
    $db
}

Export-ModuleMember -Function Get-BookRepoRoot, Get-BookPath, New-TestScratch, Invoke-IsolatedScript,
    New-FakeTool, New-RecordingAz, New-FakeSqlCmd, Get-AzMutations, Get-ScriptAst,
    Import-BookTestEnvironment, Get-BookEvidencePath, Get-BookLiveContext, Invoke-BookScript,
    Start-BookBackground, Stop-BookBackground, Wait-BookBackground, Get-BookSqlCmd, Invoke-BookSql, Get-BookScalar,
    Copy-BookSql, Get-BookValue, Wait-BookCondition, Get-BookHttp, Get-BookState, Set-BookState,
    Invoke-BookAz, Test-BookTestTag, Assert-BookDatabase
