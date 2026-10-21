<#
.SYNOPSIS
    Stop Ward General and its local DAB endpoint when they are running.

.DESCRIPTION
    Reuses the Ward General shutdown script, then inspects the owner of the DAB
    port. It stops only a process whose executable or command line identifies
    Data API Builder; any unrelated listener is reported and left alone.
#>
#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param([int] $DabPort = 5000)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$appShutdown = Join-Path $here '..' '..' 'ch04-first-app' 'shutdown.ps1'
& $appShutdown -WhatIf:$WhatIfPreference

# Process IDs listening on a port. Get-NetTCPConnection is Windows-only, so
# macOS and Linux use lsof, as examples/ch04-first-app/shutdown.ps1 does.
function Get-PortOwnerId([int] $Port) {
    if ($IsWindows) {
        Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue |
            ForEach-Object { $_.OwningProcess }
        return
    }
    if (-not (Get-Command lsof -ErrorAction SilentlyContinue)) { return }
    & lsof -nP -t -iTCP:$Port -sTCP:LISTEN 2>$null | ForEach-Object { [int]$_ }
}

# A process's full command line. Win32_Process is Windows-only; ps elsewhere.
function Get-ProcessCommandLine([int] $ProcessId) {
    if ($IsWindows) {
        return (Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" `
            -ErrorAction SilentlyContinue).CommandLine
    }
    (& ps -o command= -p $ProcessId 2>$null | Out-String).Trim()
}

$ownerId = Get-PortOwnerId $DabPort | Select-Object -First 1
if (-not $ownerId) {
    Write-Host 'The DAB endpoint is not running.' -ForegroundColor Yellow
    return
}

$process = Get-Process -Id $ownerId -ErrorAction SilentlyContinue
$commandLine = Get-ProcessCommandLine $ownerId
$isDab = $process.ProcessName -ieq 'dab' -or
    $commandLine -match '(?i)(Microsoft\.DataApiBuilder|\bdab(?:\.exe)?\s+start\b)'
if (-not $isDab) {
    throw "Port $DabPort is held by '$($process.ProcessName)' (PID $ownerId), not a recognized DAB process. It was left running."
}

if ($PSCmdlet.ShouldProcess(
    "$($process.ProcessName) (PID $ownerId) on port $DabPort",
    'Stop Data API Builder'
)) {
    Stop-Process -Id $ownerId -Force
    Write-Host 'DAB stopped.' -ForegroundColor Green
}
