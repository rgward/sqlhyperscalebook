#requires -Version 7.0
# Live tier - Chapter 2: deploy, seed, and verify the Hyperscale database.
# Run through tests/Invoke-BookTests.ps1 -Live, never directly.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'lib' 'BookTest.psm1') -Force
    $ctx = Get-BookLiveContext
    $ch = 'examples/ch02-getting-started'
    $script:existing = [bool](Invoke-BookAz sql db show --resource-group $ctx.ResourceGroup --server $ctx.Server --name $ctx.Database)
}

Describe 'Chapter 2 - cost estimate' -Tag 'Ch02' {
    It 'prints the monthly estimate (estimate-cost.ps1)' {
        $r = Invoke-BookScript -Script "$ch/estimate-cost.ps1" -Arguments "-Loc '$($ctx.Location)'" -Name 'ch02/estimate-cost' -TimeoutMinutes 5
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }
}

Describe 'Chapter 2 - deploy, seed, verify' -Tag 'Ch02' {
    It 'provisions the server and database (provision-hyperscale.ps1)' {
        if ($script:existing) { Set-ItResult -Skipped -Because 'the test database already exists (kept from an earlier run)' }
        $r = Invoke-BookScript -Script "$ch/provision-hyperscale.ps1" -Name 'ch02/provision-hyperscale' -TimeoutMinutes 60
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        $db = Assert-BookDatabase
        $db.currentServiceObjectiveName | Should -Be 'HS_Gen5_8'
        Test-BookTestTag (Invoke-BookAz group show --name $ctx.ResourceGroup) | Should -BeTrue -Because 'teardown deletes only a group tagged booktest=true'
    }

    It 'confirms the client firewall rule (preflight-firewall.ps1 -Yes)' {
        $r = Invoke-BookScript -Script "$ch/preflight-firewall.ps1" -Arguments "-Server '$($ctx.Server)' -ResourceGroup '$($ctx.ResourceGroup)' -Yes" -Name 'ch02/preflight-firewall' -TimeoutMinutes 10
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }

    It 'proves it is SQL Server on Hyperscale (connect-and-verify.sql)' {
        $r = Invoke-BookSql -File "$ch/connect-and-verify.sql" -Name 'ch02/connect-and-verify'
        $r.Text | Should -Match 'Hyperscale'
    }

    It 'creates the schema (01-04)' {
        if ($script:existing) { Set-ItResult -Skipped -Because 'the schema is created once; a kept environment already has it' }
        foreach ($f in '01-schemas.sql', '02-tables.sql', '03-views.sql', '04-procedures.sql') {
            $null = Invoke-BookSql -File "$ch/$f" -Name "ch02/$($f -replace '\.sql$')"
        }
    }

    It 'seeds about 12 GB of synthetic data (05-seed.sql)' {
        if ($script:existing) { Set-ItResult -Skipped -Because 'a kept environment is already seeded' }
        $null = Invoke-BookSql -File "$ch/05-seed.sql" -Name 'ch02/05-seed' -TimeoutMinutes 90
    }

    It 'passes every data check (verify-data.sql)' {
        $r = Invoke-BookSql -File "$ch/verify-data.sql" -Name 'ch02/verify-data' -TimeoutMinutes 20
        $r.Text | Should -Match 'ALL CHECKS PASSED'
    }

    It 'summarizes the deployment from the Activity Log (verify-activity-log.ps1)' {
        $r = Invoke-BookScript -Script "$ch/verify-activity-log.ps1" -Name 'ch02/verify-activity-log' -TimeoutMinutes 10
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }
}

Describe 'Chapter 2 - named replica' -Tag 'Ch02' {
    It 'creates wardgeneral-research (add-replicas.ps1)' {
        $replica = Invoke-BookAz sql db show --resource-group $ctx.ResourceGroup --server $ctx.Server --name $ctx.NamedReplica
        if ($replica) { Set-ItResult -Skipped -Because 'the named replica already exists' }
        $r = Invoke-BookScript -Script "$ch/add-replicas.ps1" -Name 'ch02/add-replicas' -TimeoutMinutes 45
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        Invoke-BookAz sql db show --resource-group $ctx.ResourceGroup --server $ctx.Server --name $ctx.NamedReplica |
            Should -Not -BeNullOrEmpty
    }

    It 'accepts read connections on the named replica' {
        $edition = Get-BookScalar -Query "SELECT DATABASEPROPERTYEX(DB_NAME(), 'Updateability')" -Database $ctx.NamedReplica -Name 'ch02/named-replica-updateability'
        $edition | Should -Be 'READ_ONLY'
    }
}
