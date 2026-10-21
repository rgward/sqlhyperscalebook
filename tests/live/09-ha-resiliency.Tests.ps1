#requires -Version 7.0
# Live tier - Chapter 9: failover with application retry, PITR, and geo-replica.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'lib' 'BookTest.psm1') -Force
    $ctx = Get-BookLiveContext
    $ch = 'examples/ch09-ha-resiliency'
    $null = Assert-BookDatabase
    $restored = 'wardgeneral-pitr-demo'
}

Describe 'Chapter 9 - failover and application retry' -Tag 'Ch09' {
    It 'passes the health pre-check (check-failover-health.ps1)' {
        $out = Split-Path (Get-BookEvidencePath 'ch09/failover-evidence/.keep') -Parent
        $r = Invoke-BookScript -Script "$ch/failover/check-failover-health.ps1" -Arguments "-OutputDirectory '$out'" -Name 'ch09/check-failover-health' -TimeoutMinutes 10
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        Get-BookValue -Text $r.Text -Key 'FailoverHealthPrecheck' | Should -Be 'PASS'
    }

    It 'previews the failover without requesting it (trigger-failover.ps1)' {
        $r = Invoke-BookScript -Script "$ch/failover/trigger-failover.ps1" -Name 'ch09/trigger-failover-preview' -TimeoutMinutes 5
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        $r.Text | Should -Not -Match 'FailoverRequestedUtc='
    }

    It 'fails over while the retry probe keeps working (run-retry-probe.ps1 + trigger-failover.ps1 -Execute)' {
        $out = Split-Path (Get-BookEvidencePath 'ch09/failover-evidence/.keep') -Parent
        $script:failoverStart = [DateTime]::UtcNow
        $probe = Start-BookBackground -Script "$ch/failover/run-retry-probe.ps1" -Arguments "-DurationSeconds 300 -OutputDirectory '$out'" -Name 'ch09/run-retry-probe'
        Start-Sleep -Seconds 45
        $r = Invoke-BookScript -Script "$ch/failover/trigger-failover.ps1" -Arguments '-Execute' -Name 'ch09/trigger-failover' -TimeoutMinutes 15
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        Get-BookValue -Text $r.Text -Key 'FailoverAcceptedUtc' | Should -Not -BeNullOrEmpty
        $p = Wait-BookBackground -Process $probe -TimeoutMinutes 15
        $p.ExitCode | Should -Be 0 -Because $p.LogPath
        Get-BookValue -Text $p.Text -Key 'ProbeEvidence' | Should -Not -BeNullOrEmpty
        $script:failoverEnd = [DateTime]::UtcNow
    }

    It 'collects the failover evidence (collect-failover-evidence.ps1)' {
        $out = Split-Path (Get-BookEvidencePath 'ch09/failover-evidence/.keep') -Parent
        $arguments = "-StartUtc '$($script:failoverStart.ToString('o'))' -EndUtc '$($script:failoverEnd.ToString('o'))' -OutputDirectory '$out'"
        $r = Invoke-BookScript -Script "$ch/failover/collect-failover-evidence.ps1" -Arguments $arguments -Name 'ch09/collect-failover-evidence' -TimeoutMinutes 20
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        Get-BookValue -Text $r.Text -Key 'ReplicaEvidence' | Should -Not -BeNullOrEmpty
    }

    It 'records the post-check (check-failover-health.ps1 -Phase After)' {
        $out = Split-Path (Get-BookEvidencePath 'ch09/failover-evidence/.keep') -Parent
        $r = Invoke-BookScript -Script "$ch/failover/check-failover-health.ps1" -Arguments "-Phase After -OutputDirectory '$out'" -Name 'ch09/check-failover-health-after' -TimeoutMinutes 10
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        Get-BookValue -Text $r.Text -Key 'FailoverHealthPostcheck' | Should -Be 'RECORDED'
    }
}

Describe 'Chapter 9 - point-in-time restore' -Tag 'Ch09' {
    It 'captures a restore point (prepare-pitr.ps1)' {
        $r = Invoke-BookScript -Script "$ch/pitr/prepare-pitr.ps1" -Name 'ch09/prepare-pitr' -TimeoutMinutes 10
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        $script:restorePoint = Get-BookValue -Text $r.Text -Key 'RestorePointUtc'
        $script:restorePoint | Should -Not -BeNullOrEmpty
    }

    It 'previews the restore (pitr-restore.ps1)' {
        $r = Invoke-BookScript -Script "$ch/pitr/pitr-restore.ps1" -Arguments "-RestorePointUtc '$($script:restorePoint)'" -Name 'ch09/pitr-restore-preview' -TimeoutMinutes 10
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        $r.Text | Should -Not -Match 'RestoreSubmitted='
    }

    It 'submits the restore (pitr-restore.ps1 -Execute)' {
        # Backups must cover the restore point; a just-created database can need a few minutes.
        $r = Invoke-BookScript -Script "$ch/pitr/pitr-restore.ps1" -Arguments "-RestorePointUtc '$($script:restorePoint)' -Execute" -Name 'ch09/pitr-restore' -TimeoutMinutes 30
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        Get-BookValue -Text $r.Text -Key 'RestoreSubmitted' | Should -Be $restored
    }

    It 'waits for the restore to complete (show-operation-status.ps1)' {
        $r = Invoke-BookScript -Script "$ch/pitr/show-operation-status.ps1" -Arguments '-TimeoutMinutes 120' -Name 'ch09/show-operation-status' -TimeoutMinutes 130
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        Get-BookValue -Text $r.Text -Key 'RestoreOperation' | Should -Be 'COMPLETED'
    }

    It 'validates the restored copy (verify-pitr.ps1)' {
        $r = Invoke-BookScript -Script "$ch/pitr/verify-pitr.ps1" -Name 'ch09/verify-pitr' -TimeoutMinutes 20
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        Get-BookValue -Text $r.Text -Key 'PitrVerification' | Should -Be 'PASS'
    }

    It 'previews and then deletes the restored copy (cleanup-pitr.ps1)' {
        $preview = Invoke-BookScript -Script "$ch/pitr/cleanup-pitr.ps1" -Name 'ch09/cleanup-pitr-preview' -TimeoutMinutes 5
        $preview.ExitCode | Should -Be 0 -Because $preview.LogPath
        $preview.Text | Should -Not -Match 'Deleted='
        $r = Invoke-BookScript -Script "$ch/pitr/cleanup-pitr.ps1" -Arguments '-Execute' -Name 'ch09/cleanup-pitr' -TimeoutMinutes 15
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        Get-BookValue -Text $r.Text -Key 'Deleted' | Should -Be $restored
    }

    AfterAll {
        if (Invoke-BookAz sql db show --resource-group $ctx.ResourceGroup --server $ctx.Server --name $restored) {
            $null = Invoke-BookScript -Script "$ch/pitr/cleanup-pitr.ps1" -Arguments '-Execute' -Name 'ch09/cleanup-pitr-afterall' -TimeoutMinutes 15
        }
    }
}

Describe 'Chapter 9 - geo-replica' -Tag 'Ch09', 'Geo' {
    BeforeAll {
        $geoArgs = "-TargetServer '$($ctx.GeoServer)'" + $(if ($ctx.GeoLocation) { " -TargetLocation '$($ctx.GeoLocation)'" } else { '' })
    }

    It 'previews the geo-replica (deploy-geo-replica.ps1)' {
        $r = Invoke-BookScript -Script "$ch/geo/deploy-geo-replica.ps1" -Arguments $geoArgs -Name 'ch09/deploy-geo-replica-preview' -TimeoutMinutes 10
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        $r.Text | Should -Not -Match 'GeoReplicaSubmitted='
    }

    It 'creates the target server and geo-secondary (deploy-geo-replica.ps1 -Execute)' {
        $r = Invoke-BookScript -Script "$ch/geo/deploy-geo-replica.ps1" -Arguments "$geoArgs -Execute" -Name 'ch09/deploy-geo-replica' -TimeoutMinutes 180
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        $r.Text | Should -Match 'GeoReplica(Submitted|AlreadyExists)='
    }

    It 'verifies both replication links (verify-geo-replica.ps1, waits for seeding)' {
        $ok = Wait-BookCondition -Because 'the geo-secondary to finish seeding' -TimeoutSeconds 10800 -IntervalSeconds 180 -Condition {
            $r = Invoke-BookScript -Script "$ch/geo/verify-geo-replica.ps1" -Arguments "-TargetServer '$($ctx.GeoServer)'" -Name 'ch09/verify-geo-replica' -TimeoutMinutes 10
            (Get-BookValue -Text $r.Text -Key 'GeoReplicaVerification') -eq 'PASS'
        }
        $ok | Should -BeTrue
    }

    It 'previews and then removes the geo-replica (cleanup-geo-replica.ps1)' {
        $preview = Invoke-BookScript -Script "$ch/geo/cleanup-geo-replica.ps1" -Arguments "-TargetServer '$($ctx.GeoServer)'" -Name 'ch09/cleanup-geo-replica-preview' -TimeoutMinutes 5
        $preview.ExitCode | Should -Be 0 -Because $preview.LogPath
        $r = Invoke-BookScript -Script "$ch/geo/cleanup-geo-replica.ps1" -Arguments "-TargetServer '$($ctx.GeoServer)' -Execute" -Name 'ch09/cleanup-geo-replica' -TimeoutMinutes 60
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        Get-BookValue -Text $r.Text -Key 'TargetServerDeleted' | Should -Be $ctx.GeoServer
    }

    AfterAll {
        if (Invoke-BookAz sql server show --resource-group $ctx.ResourceGroup --name $ctx.GeoServer) {
            $null = Invoke-BookScript -Script "$ch/geo/cleanup-geo-replica.ps1" -Arguments "-TargetServer '$($ctx.GeoServer)' -Execute" -Name 'ch09/cleanup-geo-replica-afterall' -TimeoutMinutes 60
        }
    }
}
