#requires -Version 7.0
<#
    Ward General Hospital Digital Chart Application
    shutdown.ps1 : stop the locally running web app and free its ports.

    run.ps1 runs the app in the foreground, so Ctrl+C is the normal way to stop
    it. This script is the backstop for when the terminal was closed instead and
    the process is still holding 7170 / 5170.

    It only stops a process whose name is in -ProcessNames (the app host, or the
    `dotnet` that launched it). Anything else listening on those ports is
    reported and left alone — a port number is not proof of identity.

    Local only; it does NOT touch Azure or the database. -WhatIf for a dry run.

    Usage:  ./shutdown.ps1
            ./shutdown.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [int[]]$Ports = @(7170, 5170),
    [string[]]$ProcessNames = @('WardGeneral.Web', 'dotnet')
)

$stopped = 0
$skipped = 0

foreach ($port in $Ports) {
    $conns = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue
    foreach ($c in $conns) {
        $procId = $c.OwningProcess
        if (-not $procId -or $procId -le 0) { continue }

        $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
        if (-not $p) { continue }

        if ($ProcessNames -notcontains $p.ProcessName) {
            Write-Warning "Port $port is held by '$($p.ProcessName)' (pid $procId), which is not the Ward General app. Leaving it alone."
            $skipped++
            continue
        }

        if ($PSCmdlet.ShouldProcess("$($p.ProcessName) (pid $procId) on port $port", 'Stop-Process')) {
            Write-Host "Stopping $($p.ProcessName) (pid $procId) on port $port ..." -ForegroundColor DarkGray
            Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
            $stopped++
        }
    }
}

# The browser-opener job run.ps1 starts, if it outlived the app.
Get-Job -Name 'wardgeneral-open-browser' -ErrorAction SilentlyContinue |
    Remove-Job -Force -ErrorAction SilentlyContinue

if ($stopped -gt 0) {
    Write-Host "Shutdown complete ($stopped process(es) stopped)." -ForegroundColor Green
}
elseif ($skipped -gt 0) {
    Write-Host "Nothing stopped. $skipped port(s) are in use by something else." -ForegroundColor Yellow
}
else {
    Write-Host "The Ward General app is not running." -ForegroundColor Yellow
}
