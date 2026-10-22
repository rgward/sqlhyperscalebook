#requires -Version 7.0
# Live tier - Chapter 4: build and run the Ward General app.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'lib' 'BookTest.psm1') -Force
    $ctx = Get-BookLiveContext
    $ch = 'examples/ch04-first-app'
    $null = Assert-BookDatabase
    $script:encounterId = Get-BookScalar -Name 'ch04/active-encounter' `
        -Query "SELECT TOP (1) EncounterId FROM clinical.Encounter WHERE Status = N'Active' ORDER BY EncounterId"
    Set-BookState -Key 'EncounterId' -Value $script:encounterId
}

Describe 'Chapter 4 - build and start the app' -Tag 'Ch04' {
    It 'builds the solution (build.ps1)' {
        $r = Invoke-BookScript -Script "$ch/build.ps1" -Arguments '-SkipPreflight' -Name 'ch04/build' -TimeoutMinutes 20
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        $r.Text | Should -Match 'Build succeeded'
    }

    It 'passes the run pre-flight (preflight-run.ps1)' {
        $r = Invoke-BookScript -Script "$ch/preflight-run.ps1" -Arguments '-SkipFirewall' -Name 'ch04/preflight-run' -TimeoutMinutes 10
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }

    It 'passes the database pre-flight (preflight-database.sql)' {
        $r = Invoke-BookSql -File "$ch/preflight-database.sql" -Name 'ch04/preflight-database'
        $r.ExitCode | Should -Be 0
    }

    It 'starts the app in the background (start-demo.ps1)' {
        $r = Invoke-BookScript -Script "$ch/start-demo.ps1" -Arguments '-NoBrowser -SkipFirewall' -Name 'ch04/start-demo' -TimeoutMinutes 15
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        (Get-BookHttp "$($ctx.AppUrl)/healthz").StatusCode | Should -Be 200
    }

    It 'serves the unit board and a patient chart' {
        $board = Get-BookHttp "$($ctx.AppUrl)/" -TimeoutSeconds 90
        $board.StatusCode | Should -Be 200
        $board.Content | Should -Match 'Unit board'
        $script:encounterId | Should -Not -BeNullOrEmpty -Because 'the seed has active encounters'
        (Get-BookHttp "$($ctx.AppUrl)/chart/$($script:encounterId)" -TimeoutSeconds 90).StatusCode | Should -Be 200
    }

    It 'stops the app (shutdown.ps1)' {
        $r = Invoke-BookScript -Script "$ch/shutdown.ps1" -Arguments '-Confirm:$false' -Name 'ch04/shutdown' -TimeoutMinutes 5
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        Wait-BookCondition -Because 'the app to stop answering' -TimeoutSeconds 60 -IntervalSeconds 5 -Condition {
            -not (Get-BookHttp "$($ctx.AppUrl)/healthz" -TimeoutSeconds 5)
        } | Should -BeTrue
    }
}

Describe 'Chapter 4 - foreground launcher' -Tag 'Ch04' {
    It 'serves the app from run.ps1' {
        $script:run = Start-BookBackground -Script "$ch/run.ps1" -Arguments '-NoBrowser -SkipFirewall' -Name 'ch04/run'
        Wait-BookCondition -Because 'run.ps1 to serve /healthz' -TimeoutSeconds 300 -IntervalSeconds 10 -Condition {
            Get-BookHttp "$($ctx.AppUrl)/healthz" -TimeoutSeconds 5
        } | Should -Not -BeNullOrEmpty
    }

    AfterAll {
        $null = Invoke-BookScript -Script "$ch/shutdown.ps1" -Arguments '-Confirm:$false' -Name 'ch04/run-shutdown' -TimeoutMinutes 5
        Stop-BookBackground $script:run
    }
}
