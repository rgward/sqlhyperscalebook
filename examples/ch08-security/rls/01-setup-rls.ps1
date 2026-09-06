<#
.SYNOPSIS
    Prepare the already-built Ward General application for the Chapter 8 RLS example.

.DESCRIPTION
    Stops recognized Ward General and DAB processes when present, deploys the
    Chapter 8 RLS policy, rebuilds the cumulative application, and generates
    and validates the secured DAB configuration. This script finishes; it does
    not start either long-running process.
#>
#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $Server,
    [string] $Database,
    [int] $DabPort = 5000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$chapter4 = Join-Path $here '..' '..' 'ch04-first-app'

& (Join-Path $here 'stop-local-apps.ps1') -DabPort $DabPort
& (Join-Path $here 'enable-rls.ps1') -Server $Server -Database $Database
& (Join-Path $chapter4 'build.ps1')

$generatedConfig = @(& (Join-Path $here '02-run-secured-dab.ps1') `
    -Server $Server -Database $Database -Port $DabPort -PrepareOnly) |
    Select-Object -Last 1
if (-not (Test-Path $generatedConfig)) {
    throw "Secured DAB config was not generated: $generatedConfig"
}

Write-Host ''
Write-Host 'Chapter 8 RLS setup is complete.' -ForegroundColor Green
Write-Host 'Open two visible terminals and run:' -ForegroundColor Cyan
Write-Host '  Terminal 1: ./examples/ch08-security/rls/02-run-secured-dab.ps1'
Write-Host '  Terminal 2: ./examples/ch08-security/rls/03-run-rls-app.ps1'
