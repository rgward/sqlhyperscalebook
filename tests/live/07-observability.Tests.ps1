#requires -Version 7.0
# Live tier - Chapter 7: performance, availability, and engine events.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'lib' 'BookTest.psm1') -Force
    $ctx = Get-BookLiveContext
    $ch = 'examples/ch07-observability'
    $null = Assert-BookDatabase
}

# First, as the README advises: Azure takes from minutes to hours to start
# sending a new diagnostic setting's errors, so the route is set up before the
# other examples and checked at the end.
Describe 'Chapter 7 - AzureSQLErrors setup' -Tag 'Ch07', 'LogAnalytics' {
    It 'previews the setup (setup-azuresqlerrors.ps1 -WhatIf)' {
        $r = Invoke-BookScript -Script "$ch/engineevents/azuresqlerrors/setup-azuresqlerrors.ps1" -Arguments '-WhatIf' -Name 'ch07/setup-azuresqlerrors-whatif' -TimeoutMinutes 10
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }

    It 'routes errors to Log Analytics (setup-azuresqlerrors.ps1)' {
        $r = Invoke-BookScript -Script "$ch/engineevents/azuresqlerrors/setup-azuresqlerrors.ps1" -Arguments '-Confirm:$false' -Name 'ch07/setup-azuresqlerrors' -TimeoutMinutes 15
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }
}

Describe 'Chapter 7 - performance investigation' -Tag 'Ch07' {
    It 'runs the cold-cache concurrent scans and drill-down (run-performance-demo.ps1)' {
        $out = Get-BookEvidencePath 'ch07/perf-evidence/.keep'
        $r = Invoke-BookScript -Script "$ch/perf/run-performance-demo.ps1" -Arguments "-OutputDirectory '$(Split-Path $out -Parent)'" -Name 'ch07/run-performance-demo' -TimeoutMinutes 90
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        $r.Text | Should -Match 'Investigation complete'
    }
}

Describe 'Chapter 7 - availability' -Tag 'Ch07' {
    It 'collects health, replicas, and metrics (run-availability.ps1)' {
        $out = Split-Path (Get-BookEvidencePath 'ch07/availability-evidence/.keep') -Parent
        $r = Invoke-BookScript -Script "$ch/availability/run-availability.ps1" -Arguments "-OutputDirectory '$out'" -Name 'ch07/run-availability' -TimeoutMinutes 20
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }

    It 'reads connection history (run-connection-history.ps1)' {
        $r = Invoke-BookScript -Script "$ch/engineevents/connections/run-connection-history.ps1" -Name 'ch07/run-connection-history' -TimeoutMinutes 10
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }
}

Describe 'Chapter 7 - Extended Events health session' -Tag 'Ch07' {
    It 'starts wardgeneral_health (setup-xevent-health.ps1)' {
        $r = Invoke-BookScript -Script "$ch/engineevents/xevent/setup-xevent-health.ps1" -Name 'ch07/setup-xevent-health' -TimeoutMinutes 10
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }

    It 'generates system error 208 (test-xevent-health.sql)' {
        $r = Invoke-BookSql -File "$ch/engineevents/xevent/test-xevent-health.sql" -Name 'ch07/test-xevent-health' -AllowFailure
        $r.ExitCode | Should -Not -Be 0 -Because 'the nonzero exit is the expected test result'
        $r.Text | Should -Match 'CH07_ThisTableDoesNotExist'
    }

    It 'reads error 208 from the ring buffer (read-xevent-health.sql)' {
        $r = Invoke-BookSql -File "$ch/engineevents/xevent/read-xevent-health.sql" -Name 'ch07/read-xevent-health'
        $r.Text | Should -Match '\b208\b'
    }

    It 'previews the teardown (teardown-xevent-health.ps1 -WhatIf)' {
        $r = Invoke-BookScript -Script "$ch/engineevents/xevent/teardown-xevent-health.ps1" -Arguments '-WhatIf' -Name 'ch07/teardown-xevent-whatif' -TimeoutMinutes 5
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }

    AfterAll {
        $null = Invoke-BookScript -Script "$ch/engineevents/xevent/teardown-xevent-health.ps1" -Arguments '-Confirm:$false' -Name 'ch07/teardown-xevent-health' -TimeoutMinutes 5
    }
}

Describe 'Chapter 7 - AzureSQLErrors in Log Analytics' -Tag 'Ch07', 'LogAnalytics' {
    It 'raises the qualifying test errors (generate-*.sql)' {
        $a = Invoke-BookSql -File "$ch/engineevents/azuresqlerrors/generate-azuresqlerror.sql" -Name 'ch07/generate-azuresqlerror' -AllowFailure
        $a.Text | Should -Match 'CH07_ENGINEEVENTS_AZURESQLERRORS_TEST'
        $b = Invoke-BookSql -File "$ch/engineevents/azuresqlerrors/generate-object-not-found.sql" -Name 'ch07/generate-object-not-found' -AllowFailure
        $b.ExitCode | Should -Not -Be 0
    }

    It 'finds the test error in AzureSQLErrors (azuresqlerrors.ps1 -Wait)' {
        # -Wait raises error 50001 and re-checks every 5 minutes until it
        # arrives; live start delays have ranged from 1 minute to about 3 hours.
        $r = Invoke-BookScript -Script "$ch/engineevents/azuresqlerrors/azuresqlerrors.ps1" -Arguments '-Wait -WaitMinutes 210 -Hours 8' -Name 'ch07/azuresqlerrors-wait' -TimeoutMinutes 225
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        $r.Text | Should -Match 'The test error has arrived in AzureSQLErrors'
        $r.Text | Should -Match 'Returned [1-9]\d* AzureSQLErrors row'
        $r.Text | Should -Match 'CH07_ENGINEEVENTS_AZURESQLERRORS_TEST'
    }

    AfterAll {
        $null = Invoke-BookScript -Script "$ch/engineevents/azuresqlerrors/teardown-azuresqlerrors.ps1" -Arguments '-PermanentlyDelete -Confirm:$false' -Name 'ch07/teardown-azuresqlerrors' -TimeoutMinutes 15
    }
}
