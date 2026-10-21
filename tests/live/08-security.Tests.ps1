#requires -Version 7.0
# Live tier - Chapter 8: Row-Level Security, auditing, and TDE with a
# customer-managed key.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'lib' 'BookTest.psm1') -Force
    $ctx = Get-BookLiveContext
    $ch = 'examples/ch08-security'
    $null = Assert-BookDatabase
    $script:encounterId = Get-BookState 'EncounterId'
    # Read before RLS is on: the admin query sees every row only without the policy.
    $script:providerId = Get-BookScalar -Name 'ch08/active-provider' `
        -Query "SELECT TOP (1) AttendingProviderId FROM clinical.Encounter WHERE Status = N'Active' ORDER BY EncounterId"
    if (-not $script:encounterId) {
        $script:encounterId = Get-BookScalar -Name 'ch08/active-encounter' `
            -Query "SELECT TOP (1) EncounterId FROM clinical.Encounter WHERE Status = N'Active' ORDER BY EncounterId"
    }

    function Start-RlsApps([string] $Name) {
        $script:securedDab = Start-BookBackground -Script "$ch/rls/02-run-secured-dab.ps1" -Name "ch08/$Name-secured-dab"
        Wait-BookCondition -Because 'the secured SQL MCP endpoint to answer' -TimeoutSeconds 240 -IntervalSeconds 10 -Condition {
            (Invoke-BookScript -Script "$ch/rls/probe-secured-mcp.ps1" -Arguments '-Quiet' -Name "ch08/$Name-probe-secured-quiet" -TimeoutMinutes 2).ExitCode -eq 0
        } | Out-Null
        $script:rlsApp = Start-BookBackground -Script "$ch/rls/03-run-rls-app.ps1" -Arguments '-NoBrowser -SkipFirewall' -Name "ch08/$Name-rls-app"
        Wait-BookCondition -Because 'the RLS-enabled app to serve /healthz' -TimeoutSeconds 420 -IntervalSeconds 10 -Condition {
            Get-BookHttp "$($ctx.AppUrl)/healthz" -TimeoutSeconds 5
        } | Out-Null
    }

    function Stop-RlsApps([string] $Name) {
        $null = Invoke-BookScript -Script "$ch/rls/stop-local-apps.ps1" -Arguments '-Confirm:$false' -Name "ch08/$Name-stop-local-apps" -TimeoutMinutes 5
        Stop-BookBackground $script:rlsApp
        Stop-BookBackground $script:securedDab
    }
}

Describe 'Chapter 8 - Row-Level Security' -Tag 'Ch08' {
    It 'inspects the starting state (00-inspect-rls-state.ps1)' {
        $r = Invoke-BookScript -Script "$ch/rls/00-inspect-rls-state.ps1" -Name 'ch08/00-inspect-rls-state' -TimeoutMinutes 5
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        $script:resetRequired = (Get-BookValue -Text $r.Text -Key 'ResetRequired') -eq 'True'
    }

    It 'previews the reset (00-reset-rls.ps1 -WhatIf)' {
        $r = Invoke-BookScript -Script "$ch/rls/00-reset-rls.ps1" -Arguments '-WhatIf' -Name 'ch08/00-reset-rls-whatif' -TimeoutMinutes 5
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }

    It 'resets to a clean state when required (00-reset-rls.ps1, 00-verify-clean.sql)' {
        if ($script:resetRequired) {
            $r = Invoke-BookScript -Script "$ch/rls/00-reset-rls.ps1" -Arguments '-Confirm:$false' -Name 'ch08/00-reset-rls' -TimeoutMinutes 10
            $r.ExitCode | Should -Be 0 -Because $r.LogPath
        }
        $null = Invoke-BookSql -File "$ch/rls/00-verify-clean.sql" -Name 'ch08/00-verify-clean'
    }

    It 'installs RLS, rebuilds the app, and prepares secured DAB (01-setup-rls.ps1)' {
        $r = Invoke-BookScript -Script "$ch/rls/01-setup-rls.ps1" -Name 'ch08/01-setup-rls' -TimeoutMinutes 30
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        $r.Text | Should -Match 'Chapter 8 RLS setup is complete'
    }

    It 'verifies the policy (verify-rls.sql)' {
        $null = Invoke-BookSql -File "$ch/rls/verify-rls.sql" -Name 'ch08/verify-rls'
    }

    It 'serves the secured MCP endpoint and the RLS app (02/03, probe-secured-mcp.ps1)' {
        Start-RlsApps 'rls'
        $r = Invoke-BookScript -Script "$ch/rls/probe-secured-mcp.ps1" -Name 'ch08/probe-secured-mcp' -TimeoutMinutes 2
        $r.Text | Should -Match 'authenticated tools'
        (Get-BookHttp "$($ctx.AppUrl)/healthz").StatusCode | Should -Be 200
    }

    It 'calls a secured tool as a provider (test-secured-tool.ps1)' {
        if (-not $script:providerId) { Set-ItResult -Skipped -Because 'no active provider was found before RLS was enabled' }
        $r = Invoke-BookScript -Script "$ch/rls/test-secured-tool.ps1" -Arguments "-ProviderId $($script:providerId)" -Name 'ch08/test-secured-tool' -TimeoutMinutes 5
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }

    AfterAll { Stop-RlsApps 'rls' }
}

Describe 'Chapter 8 - auditing' -Tag 'Ch08', 'LogAnalytics' {
    BeforeAll { $script:auditStart = [DateTime]::UtcNow.AddMinutes(-1) }

    It 'previews the audit setup (setup-auditing.ps1 -WhatIf)' {
        $r = Invoke-BookScript -Script "$ch/auditing/setup-auditing.ps1" -Arguments '-WhatIf' -Name 'ch08/setup-auditing-whatif' -TimeoutMinutes 10
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }

    It 'starts auditing to Log Analytics (setup-auditing.ps1)' {
        $script:auditStart = [DateTime]::UtcNow
        $r = Invoke-BookScript -Script "$ch/auditing/setup-auditing.ps1" -Arguments '-Confirm:$false' -Name 'ch08/setup-auditing' -TimeoutMinutes 15
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }

    It 'shows the app session context (probe-session-context.ps1)' {
        $r = Invoke-BookScript -Script "$ch/auditing/probe-session-context.ps1" -Name 'ch08/probe-session-context' -TimeoutMinutes 10
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }

    It 'opens a patient chart in the app' {
        Start-RlsApps 'audit'
        (Get-BookHttp "$($ctx.AppUrl)/chart/$($script:encounterId)" -TimeoutSeconds 120).StatusCode | Should -Be 200
    }

    It 'finds the app activity in the audit log (query-audit.ps1, waits for routing and delivery)' {
        # A new audit destination can take up to 90 minutes to start receiving
        # events, and activity before then is never retained: open a chart each poll.
        $script:auditPoll = 0
        $found = Wait-BookCondition -Because 'audit rows to arrive (routing start + asynchronous delivery)' -TimeoutSeconds 6000 -IntervalSeconds 300 -Condition {
            $script:auditPoll++
            $null = Get-BookHttp "$($ctx.AppUrl)/chart/$($script:encounterId)" -TimeoutSeconds 120
            $end = [DateTime]::UtcNow.ToString('o')
            $start = $script:auditStart.ToString('o')
            $r = Invoke-BookScript -Script "$ch/auditing/query-audit.ps1" -Arguments "-StartUtc '$start' -EndUtc '$end'" -Name "ch08/query-audit-$($script:auditPoll)" -TimeoutMinutes 10
            $r.ExitCode | Should -Be 0 -Because "query-audit.ps1 must not fail while waiting for the first audit record ($($r.LogPath))"
            $r.Text -match 'Returned [1-9]\d* audit row'
        }
        $found | Should -BeTrue
    }

    AfterAll {
        Stop-RlsApps 'audit'
        $null = Invoke-BookScript -Script "$ch/auditing/teardown-auditing.ps1" -Arguments '-Confirm:$false' -Name 'ch08/teardown-auditing' -TimeoutMinutes 15
    }
}

Describe 'Chapter 8 - TDE with a customer-managed key' -Tag 'Ch08', 'Tde' {
    It 'makes a Key Vault key the server TDE protector (provision-tde-cmk.ps1)' {
        $protector = Invoke-BookAz sql server tde-key show --resource-group $ctx.ResourceGroup --server $ctx.Server
        if ($protector -and $protector.serverKeyType -eq 'AzureKeyVault') {
            Set-ItResult -Skipped -Because 'the server already uses a customer-managed key (kept environment)'
        }
        $arguments = "-Rg '$($ctx.ResourceGroup)' -Server '$($ctx.Server)' -Database '$($ctx.Database)' -Loc '$($ctx.Location)' -Vault '$($ctx.TdeVault)'"
        $r = Invoke-BookScript -Script "$ch/tde/provision-tde-cmk.ps1" -Arguments $arguments -Name 'ch08/provision-tde-cmk' -TimeoutMinutes 30
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        (Invoke-BookAz sql server tde-key show --resource-group $ctx.ResourceGroup --server $ctx.Server).serverKeyType |
            Should -Be 'AzureKeyVault'
        Set-BookState -Key 'TdeVault' -Value $ctx.TdeVault
    }
}
