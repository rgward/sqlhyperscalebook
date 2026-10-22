#requires -Version 7.0
# Offline tier - preview gates and safety refusals. Every billable or
# destructive example previews by default. These tests run the scripts against
# a recording fake `az` and check that a preview changes nothing, that the gate
# switch makes exactly the intended change, and that the guards refuse.

BeforeDiscovery {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:gated = Get-ChildItem (Join-Path $root 'examples') -Recurse -Filter *.ps1 |
        Where-Object { $_.FullName -notmatch '[\\/](bin|obj)[\\/]' } |
        Where-Object { (Get-Content $_.FullName -Raw) -match '\[switch\]\s*\$(Execute|Approve|ApproveScaling|Apply)\b' } |
        ForEach-Object { @{ Name = $_.FullName.Substring($root.Length + 1) -replace '\\', '/'; Path = $_.FullName } }
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'lib' 'BookTest.psm1') -Force

    $script:server = 'collierhealth-test'
    $script:sourceId = "/subscriptions/0/resourceGroups/rg-collierhealth/providers/Microsoft.Sql/servers/$server/databases/wardgeneral"
    $script:baseEnv = @{
        RG                    = 'rg-collierhealth'
        WardGeneral__Server   = "$server.database.windows.net"
        WardGeneral__Database = 'wardgeneral'
    }
    $script:sourceJson = (@{
        id = $sourceId; name = 'wardgeneral'; status = 'Online'; edition = 'Hyperscale'; location = 'westus3'
        currentServiceObjectiveName = 'HS_Gen5_8'; serviceObjective = 'HS_Gen5_8'; capacity = 8; family = 'Gen5'
        requestedBackupStorageRedundancy = 'Geo'; currentBackupStorageRedundancy = 'Geo'
        highAvailabilityReplicaCount = 1; zoneRedundant = $true; sourceDatabaseId = $null; secondaryType = $null
        earliestRestoreDate = '2026-01-01T00:00:00Z'
    } | ConvertTo-Json -Compress)

    function Invoke-WithAz {
        param(
            [string] $Script,
            [string] $Arguments = '',
            [System.Collections.IDictionary] $Responses = [ordered]@{},
            [hashtable] $Environment = @{}
        )
        $az = New-RecordingAz -Responses $Responses
        $env = $script:baseEnv.Clone()
        foreach ($k in $az.Environment.Keys) { $env[$k] = $az.Environment[$k] }
        foreach ($k in $Environment.Keys) { $env[$k] = $Environment[$k] }
        $r = Invoke-IsolatedScript -Script $Script -Arguments $Arguments -Environment $env
        $log = $az.LogPath
        $calls = if (Test-Path $log) { @(Get-Content $log) } else { @() }
        $r | Add-Member -NotePropertyName Calls -NotePropertyValue $calls
        $r | Add-Member -NotePropertyName Mutations -NotePropertyValue @(Get-AzMutations -LogPath $log) -PassThru
    }
}

Describe 'Gated scripts (static)' -Tag 'Offline' {
    It '<Name> makes no mutating az call before its gate' -ForEach $script:gated {
        $lines = Get-Content -LiteralPath $Path
        $gate = ($lines | Select-String -Pattern 'if \(-not \$(Execute|Approve|ApproveScaling|Apply)\)' | Select-Object -First 1).LineNumber
        $gate | Should -BeGreaterThan 0 -Because 'a gated script must test its switch with if (-not $Switch)'
        $before = $lines[0..($gate - 2)] -join "`n"
        $before | Should -Not -Match '(?m)^[ \t]*(\$\w+[ \t]*=[ \t]*)?az[ \t]+(\S+[ \t]+)*(create|update|delete|restore|failover|purge|delete-link)\b'
        $before | Should -Not -Match 'az[ \t]+rest[ \t]+--method[ \t]+(post|put|patch|delete)'
    }
}

Describe 'trigger-failover.ps1' -Tag 'Offline' {
    BeforeAll { $s = 'examples/ch09-ha-resiliency/failover/trigger-failover.ps1' }

    It 'previews the failover request without sending it' {
        $r = Invoke-WithAz $s
        $r.ExitCode | Should -Be 0 -Because $r.Text
        $r.Text | Should -Match 'PREVIEW ONLY'
        $r.Text | Should -Match 'POST https://management\.azure\.com/.*/failover\?api-version='
        $r.Mutations | Should -BeNullOrEmpty
    }

    It 'sends exactly one failover POST with -Execute' {
        $r = Invoke-WithAz $s '-Execute'
        $r.ExitCode | Should -Be 0 -Because $r.Text
        $r.Mutations.Count | Should -Be 1
        $r.Mutations[0] | Should -Match '^rest --method post --url \S+/databases/wardgeneral/failover\?api-version='
        $r.Text | Should -Match 'FailoverAcceptedUtc='
    }

    It 'refuses a database that is not Hyperscale' {
        $r = Invoke-WithAz $s '-Execute' -Responses ([ordered]@{ '^sql db show' = ($sourceJson -replace '"Hyperscale"', '"GeneralPurpose"') })
        $r.ExitCode | Should -Not -Be 0
        $r.Text | Should -Match 'not Hyperscale'
        $r.Mutations | Should -BeNullOrEmpty
    }
}

Describe 'scale-compute.ps1' -Tag 'Offline' {
    BeforeAll { $s = 'examples/ch10-performance/01-scale-compute/scale-compute.ps1' }

    It 'previews a scale without changing the database' {
        $r = Invoke-WithAz $s '-TargetServiceObjective HS_Gen5_16' -Responses ([ordered]@{ '^sql db show' = $sourceJson })
        $r.ExitCode | Should -Be 0 -Because $r.Text
        $r.Text | Should -Match 'Re-run with -Approve'
        $r.Mutations | Should -BeNullOrEmpty
    }

    It 'scales with -Approve' {
        $r = Invoke-WithAz $s '-TargetServiceObjective HS_Gen5_16 -Approve' -Responses ([ordered]@{ '^sql db show' = $sourceJson })
        $r.ExitCode | Should -Be 0 -Because $r.Text
        $r.Mutations.Count | Should -Be 1
        $r.Mutations[0] | Should -Match '^sql db update .*--service-objective HS_Gen5_16'
    }

    It 'does nothing when the database is already at the target' {
        $r = Invoke-WithAz $s '-TargetServiceObjective HS_Gen5_8 -Approve' -Responses ([ordered]@{ '^sql db show' = $sourceJson })
        $r.Text | Should -Match 'already at the requested service objective'
        $r.Mutations | Should -BeNullOrEmpty
    }

    It 'warns before moving serverless to provisioned compute' {
        $r = Invoke-WithAz $s '-TargetServiceObjective HS_Gen5_16' -Responses ([ordered]@{ '^sql db show' = ($sourceJson -replace 'HS_Gen5_8', 'HS_S_Gen5_8') })
        $r.Text | Should -Match 'from serverless \(HS_S_Gen5_8\) to provisioned'
        $r.Mutations | Should -BeNullOrEmpty
    }
}

Describe 'pitr-restore.ps1' -Tag 'Offline' {
    BeforeAll {
        $s = 'examples/ch09-ha-resiliency/pitr/pitr-restore.ps1'
        $point = "-RestorePointUtc '2026-01-02T03:04:05Z'"
        $noTarget = [ordered]@{ '^sql db list' = '' }
    }

    It 'previews a serverless restore named wardgeneral-pitr-demo' {
        $r = Invoke-WithAz $s $point -Responses $noTarget
        $r.ExitCode | Should -Be 0 -Because $r.Text
        $r.Text | Should -Match 'Target DB \(new\)\s+: wardgeneral-pitr-demo'
        $r.Text | Should -Match 'HS_S_Gen5_8 \(serverless'
        $r.Text | Should -Match 'PREVIEW ONLY'
        $r.Mutations | Should -BeNullOrEmpty
    }

    It 'submits the restore with -Execute' {
        $r = Invoke-WithAz $s "$point -Execute" -Responses $noTarget
        $r.ExitCode | Should -Be 0 -Because $r.Text
        $r.Mutations.Count | Should -Be 1
        $r.Mutations[0] | Should -Match '^sql db restore .*--dest-name wardgeneral-pitr-demo .*--time 2026-01-02T03:04:05\.0000000Z .*--service-objective HS_S_Gen5_8'
        $r.Text | Should -Match 'RestoreSubmitted=wardgeneral-pitr-demo'
    }

    It 'refuses when the target already exists' {
        $r = Invoke-WithAz $s "$point -Execute" -Responses ([ordered]@{ '^sql db list' = 'wardgeneral-pitr-demo' })
        $r.ExitCode | Should -Not -Be 0
        $r.Text | Should -Match 'already exists'
        $r.Mutations | Should -BeNullOrEmpty
    }

    It 'refuses a target outside the demo (<Arguments>)' -ForEach @(
        @{ Arguments = '-RestoredDatabase wardgeneral'; Expect = 'outside this demo' }
        @{ Arguments = '-TargetServiceObjective HS_Gen5_8'; Expect = 'serverless objective' }
    ) {
        $r = Invoke-WithAz $s "$point $Arguments -Execute" -Responses $noTarget
        $r.ExitCode | Should -Not -Be 0
        $r.Text | Should -Match $Expect
        $r.Mutations | Should -BeNullOrEmpty
    }
}

Describe 'cleanup-pitr.ps1' -Tag 'Offline' {
    BeforeAll {
        $s = 'examples/ch09-ha-resiliency/pitr/cleanup-pitr.ps1'
        $restored = [ordered]@{ '^sql db show' = (@{ id = "$sourceId-pitr-demo"; name = 'wardgeneral-pitr-demo'; edition = 'Hyperscale'; sourceDatabaseId = $sourceId } | ConvertTo-Json -Compress) }
    }

    It 'previews the deletion' {
        $r = Invoke-WithAz $s -Responses $restored
        $r.ExitCode | Should -Be 0 -Because $r.Text
        $r.Text | Should -Match 'PREVIEW ONLY'
        $r.Mutations | Should -BeNullOrEmpty
    }

    It 'deletes only wardgeneral-pitr-demo with -Execute' {
        $r = Invoke-WithAz $s '-Execute' -Responses $restored
        $r.ExitCode | Should -Be 0 -Because $r.Text
        $r.Mutations.Count | Should -Be 1
        $r.Mutations[0] | Should -Match '^sql db delete .*--name wardgeneral-pitr-demo'
        $r.Text | Should -Match 'Deleted=wardgeneral-pitr-demo'
    }

    It 'refuses to delete the source database' {
        $r = Invoke-WithAz $s '-RestoredDatabase wardgeneral -Execute' -Responses $restored
        $r.ExitCode | Should -Not -Be 0
        $r.Text | Should -Match "must start with 'wardgeneral-pitr-'"
        $r.Mutations | Should -BeNullOrEmpty
    }

    It 'refuses a copy restored from a different database' {
        $other = [ordered]@{ '^sql db show' = (@{ id = 'x'; name = 'wardgeneral-pitr-demo'; edition = 'Hyperscale'; sourceDatabaseId = ($sourceId -replace 'wardgeneral$', 'other') } | ConvertTo-Json -Compress) }
        $r = Invoke-WithAz $s '-Execute' -Responses $other
        $r.ExitCode | Should -Not -Be 0
        $r.Text | Should -Match 'does not identify'
        $r.Mutations | Should -BeNullOrEmpty
    }
}

Describe 'deploy-geo-replica.ps1' -Tag 'Offline' {
    BeforeAll {
        $s = 'examples/ch09-ha-resiliency/geo/deploy-geo-replica.ps1'
        function Get-GeoResponses([string] $Paired = 'eastus') {
            [ordered]@{
                '^ad signed-in-user show'                   = '{"id":"u1","userPrincipalName":"tester@example.com","displayName":"Tester"}'
                '^sql db show .*--server collierhealth-test' = $sourceJson
                'list-locations .*pairedRegion'              = $Paired
                'list-locations'                             = 'westus3||eastus||eastus2'
                '^sql db list-editions'                      = 'HS_Gen5_8'
                '^sql server tde-key show'                   = '{"serverKeyType":"ServiceManaged","uri":null,"autoRotationEnabled":false}'
                '^sql server show'                           = 'EXIT:3|'
            }
        }
    }

    It 'previews a new server in the paired region' {
        $r = Invoke-WithAz $s '-TargetServer collierhealth-geo' -Responses (Get-GeoResponses)
        $r.ExitCode | Should -Be 0 -Because $r.Text
        $r.Text | Should -Match 'Target server\s+: collierhealth-geo \(eastus; Azure paired region of westus3\)'
        $r.Text | Should -Match 'Target server state: create new'
        $r.Text | Should -Match 'PREVIEW ONLY'
        $r.Mutations | Should -BeNullOrEmpty
    }

    It 'refuses a target in the source region' {
        $r = Invoke-WithAz $s '-TargetServer collierhealth-geo -TargetLocation westus3' -Responses (Get-GeoResponses)
        $r.ExitCode | Should -Not -Be 0
        $r.Text | Should -Match "source database's own region"
        $r.Mutations | Should -BeNullOrEmpty
    }

    It 'refuses an existing server that is not a Ward General sandbox' {
        $responses = Get-GeoResponses
        $responses['^sql server show'] = '{"location":"eastus","tags":{"application":"payroll"},"identity":{"type":"SystemAssigned","principalId":"p"}}'
        $r = Invoke-WithAz $s '-TargetServer collierhealth-geo' -Responses $responses
        $r.ExitCode | Should -Not -Be 0
        $r.Text | Should -Match 'not tagged as a Ward General sandbox'
        $r.Mutations | Should -BeNullOrEmpty
    }

    It 'refuses an invalid or identical target server name (<Target>)' -ForEach @(
        @{ Target = 'Collier_Geo' }, @{ Target = 'collierhealth-test' }
    ) {
        $r = Invoke-WithAz $s "-TargetServer $Target" -Responses (Get-GeoResponses)
        $r.ExitCode | Should -Not -Be 0
        $r.Mutations | Should -BeNullOrEmpty
    }
}

Describe 'cleanup-geo-replica.ps1' -Tag 'Offline' {
    BeforeAll {
        $s = 'examples/ch09-ha-resiliency/geo/cleanup-geo-replica.ps1'
        function Get-CleanupResponses {
            [ordered]@{
                '^sql server show'                          = '{"id":"/s/collierhealth-geo","name":"collierhealth-geo","location":"eastus","identityType":"SystemAssigned","principalId":"p","tags":{"application":"ward-general-ehr","environment":"sandbox"}}'
                '^sql db show .*--server collierhealth-geo' = "{`"id`":`"/s/geo/wardgeneral`",`"name`":`"wardgeneral`",`"status`":`"Online`",`"edition`":`"Hyperscale`",`"sourceDatabaseId`":`"$sourceId`",`"secondaryType`":`"Geo`"}"
                '^sql db show .*--server collierhealth-test' = $sourceJson
                '^sql db replica list-links'                = '[{"id":"/links/1","partnerServer":"collierhealth-geo"}]'
                '^sql db list'                              = 'master||wardgeneral'
            }
        }
    }

    It 'previews removal of the link and the target server' {
        $r = Invoke-WithAz $s '-TargetServer collierhealth-geo' -Responses (Get-CleanupResponses)
        $r.ExitCode | Should -Be 0 -Because $r.Text
        $r.Text | Should -Match 'Source retained\s+: /subscriptions/'
        $r.Text | Should -Match 'PREVIEW ONLY'
        $r.Mutations | Should -BeNullOrEmpty
    }

    It 'removes the link, then the target server, with -Execute' {
        $r = Invoke-WithAz $s '-TargetServer collierhealth-geo -Execute' -Responses (Get-CleanupResponses)
        $r.ExitCode | Should -Be 0 -Because $r.Text
        $r.Mutations.Count | Should -Be 2
        $r.Mutations[0] | Should -Match '^sql db replica delete-link .*--server collierhealth-test .*--partner-server collierhealth-geo'
        $r.Mutations[1] | Should -Match '^sql server delete .*--name collierhealth-geo'
        $r.Mutations -join "`n" | Should -Not -Match 'sql db delete'
    }

    It 'refuses when <Case>' -ForEach @(
        @{ Case = 'the target is in the source region'; Key = '^sql server show'; Value = '{"id":"x","name":"collierhealth-geo","location":"westus3","identityType":"SystemAssigned","principalId":"p","tags":{"application":"ward-general-ehr","environment":"sandbox"}}'; Expect = "source's own region" }
        @{ Case = 'the target is not a sandbox'; Key = '^sql server show'; Value = '{"id":"x","name":"collierhealth-geo","location":"eastus","identityType":"SystemAssigned","principalId":"p","tags":{"application":"payroll"}}'; Expect = 'not tagged as a Ward General sandbox' }
        @{ Case = 'the target holds other databases'; Key = '^sql db list'; Value = 'master||wardgeneral||payroll'; Expect = 'unexpected database' }
        @{ Case = 'there is no replication link'; Key = '^sql db replica list-links'; Value = '[]'; Expect = 'expected one replication link' }
    ) {
        $responses = Get-CleanupResponses
        $responses[$Key] = $Value
        $r = Invoke-WithAz $s '-TargetServer collierhealth-geo -Execute' -Responses $responses
        $r.ExitCode | Should -Not -Be 0
        $r.Text | Should -Match $Expect
        $r.Mutations | Should -BeNullOrEmpty
    }

    It 'refuses to treat the source server as the target' {
        $r = Invoke-WithAz $s '-TargetServer collierhealth-test -Execute' -Responses (Get-CleanupResponses)
        $r.ExitCode | Should -Not -Be 0
        $r.Mutations | Should -BeNullOrEmpty
    }
}

Describe 'grant-model-access.ps1' -Tag 'Offline' {
    BeforeAll {
        $s = 'examples/ch06-agentic-ai/grant-model-access.ps1'
        $agentEnv = @{ Agent__Endpoint = 'https://ward-ai.openai.azure.com/' }
        function Get-GrantResponses([string] $Roles = '', [string] $Actions = '') {
            [ordered]@{
                '^ad signed-in-user show'          = '{"id":"u1","upn":"tester@example.com"}'
                '^cognitiveservices account list' = '/subscriptions/0/resourceGroups/rg-collierhealth/providers/Microsoft.CognitiveServices/accounts/ward-ai'
                '^role assignment list'           = $Roles
                '^role definition list'           = $Actions
            }
        }
    }

    It 'previews the missing role and exits 1' {
        $r = Invoke-WithAz $s -Responses (Get-GrantResponses) -Environment $agentEnv
        $r.ExitCode | Should -Be 1
        $r.Text | Should -Match "Proposed: assign 'Cognitive Services OpenAI User'"
        $r.Mutations | Should -BeNullOrEmpty
    }

    It 'assigns the role with -Apply' {
        $r = Invoke-WithAz $s '-Apply' -Responses (Get-GrantResponses) -Environment $agentEnv
        $r.ExitCode | Should -Be 0 -Because $r.Text
        $r.Mutations.Count | Should -Be 1
        $r.Mutations[0] | Should -Match "^role assignment create .*--role Cognitive Services OpenAI User .*accounts/ward-ai"
    }

    It 'changes nothing when one existing role already allows chat completions' {
        $r = Invoke-WithAz $s '-Apply' -Environment $agentEnv `
            -Responses (Get-GrantResponses -Roles 'Cognitive Services User' -Actions 'Microsoft.CognitiveServices/*')
        $r.ExitCode | Should -Be 0 -Because $r.Text
        $r.Text | Should -Match 'OK: you can call the agent'
        $r.Mutations | Should -BeNullOrEmpty
    }
}
