#requires -Version 7.0
# Live tier - Chapter 10: compute scaling, storage growth, and tuning.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'lib' 'BookTest.psm1') -Force
    $ctx = Get-BookLiveContext
    $ch = 'examples/ch10-performance'
    $script:startSlo = (Assert-BookDatabase).currentServiceObjectiveName
}

Describe 'Chapter 10 - before the demos' -Tag 'Ch10' {
    It 'checks for geo links that would skew the results (check-geo-links.ps1)' {
        $r = Invoke-BookScript -Script "$ch/check-geo-links.ps1" -Arguments "-Server '$($ctx.Server)' -Database '$($ctx.Database)' -ResourceGroup '$($ctx.ResourceGroup)'" -Name 'ch10/check-geo-links' -TimeoutMinutes 5
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }
}

Describe 'Chapter 10 - Demo 1: scale compute 8 -> 16 -> 40' -Tag 'Ch10', 'Sqlsim' {
    It 'previews the starting shape (scale-compute.ps1 -TargetServiceObjective HS_Gen5_8)' {
        $r = Invoke-BookScript -Script "$ch/01-scale-compute/scale-compute.ps1" -Arguments '-TargetServiceObjective HS_Gen5_8' -Name 'ch10/scale-compute-preview' -TimeoutMinutes 5
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }

    It 'starts at HS_Gen5_8 (scale-compute.ps1 -Approve when needed)' {
        if ($script:startSlo -eq 'HS_Gen5_8') { Set-ItResult -Skipped -Because 'the database is already HS_Gen5_8' }
        $r = Invoke-BookScript -Script "$ch/01-scale-compute/scale-compute.ps1" -Arguments '-TargetServiceObjective HS_Gen5_8 -Approve' -Name 'ch10/scale-compute-to-8' -TimeoutMinutes 60
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }

    It 'passes the pre-flight and resets earlier demo rows (preflight.ps1 -ResetDemoData -ApproveCleanup)' {
        $r = Invoke-BookScript -Script "$ch/01-scale-compute/preflight.ps1" -Arguments '-ResetDemoData -ApproveCleanup' -Name 'ch10/demo1-preflight' -TimeoutMinutes 20
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }

    It 'previews the progression (run-demo.ps1)' {
        $r = Invoke-BookScript -Script "$ch/01-scale-compute/run-demo.ps1" -Name 'ch10/demo1-preview' -TimeoutMinutes 20
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        $r.Text | Should -Match 'ApproveScaling'
    }

    It 'runs the workload at 8, 16, and 40 vCores (run-demo.ps1 -ApproveScaling)' {
        $r = Invoke-BookScript -Script "$ch/01-scale-compute/run-demo.ps1" -Arguments '-ApproveScaling' -Name 'ch10/demo1-run' -TimeoutMinutes 180
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        $r.Text | Should -Match 'Stage 1 complete'
        (Assert-BookDatabase).currentServiceObjectiveName | Should -Be 'HS_Gen5_40'
    }
}

Describe 'Chapter 10 - Demo 2: grow the database' -Tag 'Ch10', 'Sqlsim' {
    It 'previews the growth workload (run-demo.ps1)' {
        $r = Invoke-BookScript -Script "$ch/02-grow-data/run-demo.ps1" -Arguments "-SqlsimPath '$($ctx.Sqlsim)'" -Name 'ch10/demo2-preview' -TimeoutMinutes 10
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }

    It 'drives 64 writers and captures the growth report (run-demo.ps1 -Execute)' {
        $arguments = "-Execute -WorkloadSeconds $($ctx.GrowthSeconds) -SqlsimPath '$($ctx.Sqlsim)'"
        $r = Invoke-BookScript -Script "$ch/02-grow-data/run-demo.ps1" -Arguments $arguments -Name 'ch10/demo2-run' -TimeoutMinutes 90
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        $r.Text | Should -Match 'Demo 2 growth and report capture complete'
    }
}

Describe 'Chapter 10 - Demo 3: tune the grown data' -Tag 'Ch10' {
    It 'previews and runs the JSON index demo (json-index/run-demo.ps1)' {
        $preview = Invoke-BookScript -Script "$ch/03-tune-grown-data/json-index/run-demo.ps1" -Name 'ch10/json-index-preview' -TimeoutMinutes 5
        $preview.ExitCode | Should -Be 0 -Because $preview.LogPath
        $r = Invoke-BookScript -Script "$ch/03-tune-grown-data/json-index/run-demo.ps1" -Arguments '-Execute' -Name 'ch10/json-index' -TimeoutMinutes 60
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }

    It 'previews and runs the memory grant feedback demo (memory-grant-feedback/run-demo.ps1)' {
        $preview = Invoke-BookScript -Script "$ch/03-tune-grown-data/memory-grant-feedback/run-demo.ps1" -Name 'ch10/mgf-preview' -TimeoutMinutes 5
        $preview.ExitCode | Should -Be 0 -Because $preview.LogPath
        $r = Invoke-BookScript -Script "$ch/03-tune-grown-data/memory-grant-feedback/run-demo.ps1" -Arguments '-Execute' -Name 'ch10/mgf' -TimeoutMinutes 60
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }

    It 'previews and runs the ValueNumeric index evaluation (observation-index/run-demo.ps1)' {
        $preview = Invoke-BookScript -Script "$ch/03-tune-grown-data/observation-index/run-demo.ps1" -Name 'ch10/observation-index-preview' -TimeoutMinutes 5
        $preview.ExitCode | Should -Be 0 -Because $preview.LogPath
        $r = Invoke-BookScript -Script "$ch/03-tune-grown-data/observation-index/run-demo.ps1" -Arguments '-Execute' -Name 'ch10/observation-index' -TimeoutMinutes 90
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        $left = Get-BookScalar -Name 'ch10/observation-index-dropped' `
            -Query "SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID(N'clinical.Observation') AND name = N'IX_Observation_ValueNumeric_Ch10'"
        $left | Should -Be '0' -Because 'the evaluation drops its index unless -KeepIndex'
    }
}

Describe 'Chapter 10 - retained calibration query' -Tag 'Ch10' {
    # Excluded from the workloads because its access path overruns the bounded
    # interval (see the 01-scale-compute README); it took 3-15+ minutes in live
    # runs. Its own block, so a slow run never skips the demos.
    It 'runs once without error (sql/get-patient-chart-by-bed.sql)' {
        $r = Invoke-BookSql -File "$ch/01-scale-compute/sql/get-patient-chart-by-bed.sql" -Name 'ch10/get-patient-chart-by-bed' -TimeoutMinutes 30
        $r.ExitCode | Should -Be 0
    }
}

Describe 'Chapter 10 - scale back' -Tag 'Ch10' {
    It 'returns the database to HS_Gen5_8 (scale-compute.ps1 -Approve)' {
        if ((Assert-BookDatabase).currentServiceObjectiveName -eq 'HS_Gen5_8') { Set-ItResult -Skipped -Because 'already HS_Gen5_8' }
        $r = Invoke-BookScript -Script "$ch/01-scale-compute/scale-compute.ps1" -Arguments '-TargetServiceObjective HS_Gen5_8 -Approve' -Name 'ch10/scale-back' -TimeoutMinutes 60
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        (Assert-BookDatabase).currentServiceObjectiveName | Should -Be 'HS_Gen5_8'
    }
}
