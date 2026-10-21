#requires -Version 7.0
# Live tier - Chapter 3: the architecture queries (read-only).

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'lib' 'BookTest.psm1') -Force
    $ctx = Get-BookLiveContext
    $ch = 'examples/ch03-architecture'
    $null = Assert-BookDatabase
}

Describe 'Chapter 3 - Hyperscale architecture queries' -Tag 'Ch03' {
    It 'runs <_> on the primary' -ForEach @(
        '01-four-tiers.sql', '02-primary-compute.sql', '03-log-service.sql',
        '04-page-servers.sql', '05-file-storage.sql', '06-replicas.sql'
    ) {
        $r = Invoke-BookSql -File "$ch/$_" -Name "ch03/$($_ -replace '\.sql$')"
        $r.ExitCode | Should -Be 0
    }

    It 'runs 06-replicas.sql on the named replica' {
        $r = Invoke-BookSql -File "$ch/06-replicas.sql" -Database $ctx.NamedReplica -Name 'ch03/06-replicas-named'
        $r.ExitCode | Should -Be 0
    }
}
