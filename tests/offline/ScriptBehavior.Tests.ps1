#requires -Version 7.0
# Offline tier - script behavior that earlier fixes depend on: configuration
# loading, cross-platform paths, StrictMode edge cases, and read-only checks.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'lib' 'BookTest.psm1') -Force

    function Invoke-Book {
        param(
            [string] $Script,
            [string] $Arguments = '',
            [System.Collections.IDictionary] $Az = [ordered]@{},
            [hashtable] $Environment = @{},
            [string] $Prelude = '',
            [object] $SqlCmd = $null
        )
        $fakeAz = New-RecordingAz -Responses $Az
        $env = @{ RG = 'rg-collierhealth'; WardGeneral__Server = 'collierhealth-test.database.windows.net'; WardGeneral__Database = 'wardgeneral' }
        foreach ($k in $fakeAz.Environment.Keys) { $env[$k] = $fakeAz.Environment[$k] }
        if ($SqlCmd) { foreach ($k in $SqlCmd.Environment.Keys) { $env[$k] = $SqlCmd.Environment[$k] } }
        foreach ($k in $Environment.Keys) { $env[$k] = $Environment[$k] }
        $r = Invoke-IsolatedScript -Script $Script -Arguments $Arguments -Environment $env -Prelude $Prelude
        $calls = if (Test-Path $fakeAz.LogPath) { @(Get-Content $fakeAz.LogPath) } else { @() }
        $r | Add-Member -NotePropertyName AzCalls -NotePropertyValue $calls -PassThru
    }
}

Describe 'load-env.ps1 (<Chapter>)' -Tag 'Offline' -ForEach @(
    @{ Chapter = 'ch04'; Script = 'examples/ch04-first-app/load-env.ps1'; Keys = @('WardGeneral__Server', 'WardGeneral__Database') }
    @{ Chapter = 'ch05'; Script = 'examples/ch05-ai-ready-sql/load-env.ps1'; Keys = @('RG', 'SRV', 'AI_RESOURCE') }
) {
    BeforeEach {
        $scratch = New-TestScratch 'loadenv'
        $envFile = Join-Path $scratch "$Chapter.env"
        $require = "-Require @('$($Keys -join "','")')"
        $filled = @{}; foreach ($k in $Keys) { $filled[$k] = "value-$k" }
    }

    It 'accepts exported variables when the file is missing, and copies nothing' {
        $r = Invoke-IsolatedScript -Script $Script -Arguments "-Path '$envFile' $require -Quiet" -Environment $filled
        $r.ExitCode | Should -Be 0 -Because $r.Text
        Test-Path $envFile | Should -BeFalse
    }

    It 'creates the file from the template and stops when a value is <Case>' -ForEach @(
        @{ Case = 'unset'; Value = $null }, @{ Case = 'a placeholder'; Value = '<your-value>' }
    ) {
        $partial = $filled.Clone(); $partial[$Keys[0]] = $Value
        $r = Invoke-IsolatedScript -Script $Script -Arguments "-Path '$envFile' $require -Quiet" -Environment $partial
        $r.ExitCode | Should -Not -Be 0
        $r.Text | Should -Match "No $Chapter\.env yet"
        Test-Path $envFile | Should -BeTrue
    }

    It 'lets an exported variable win over the file' {
        ($Keys | ForEach-Object { "$_=from-file" }) | Set-Content $envFile
        $probe = Join-Path $scratch 'probe.ps1'
        "& '$(Get-BookPath $Script)' -Path '$envFile' $require -Quiet; `$env:$($Keys[0])" | Set-Content $probe
        $r = Invoke-IsolatedScript -Script $probe -Environment @{ $Keys[0] = 'from-shell' }
        $r.ExitCode | Should -Be 0 -Because $r.Text
        @($r.Output | Where-Object { $_ })[-1] | Should -Be 'from-shell'
    }
}

Describe 'run-availability.ps1 (Chapter 7)' -Tag 'Offline' {
    BeforeAll {
        $s = 'examples/ch07-observability/availability/run-availability.ps1'
        $sqlcmd = New-FakeSqlCmd -Output "replica_role  synchronization_health`nPRIMARY       HEALTHY"
        function New-Event([string] $Service, [string] $Region, [string] $Name) {
            @{ name = $Name; properties = @{ eventType = 'ServiceIssue'; status = 'Resolved'; title = $Name; lastUpdateTime = '2026-01-01T00:00:00Z'
                    impact = @(@{ impactedService = $Service; impactedRegions = @(@{ impactedRegion = $Region }) }) } }
        }
        $events = @{ value = @(
                (New-Event 'Azure SQL Database' 'West US 3' 'match'),
                (New-Event 'Azure SQL Database' 'East US' 'other-region'),
                (New-Event 'Azure SQL Managed Instance' 'West US 3' 'other-service')
            ) } | ConvertTo-Json -Depth 10 -Compress
        $availability = '{"value":[{"name":{"value":"availability"},"timeseries":[{"data":[{"average":100,"minimum":100},{"average":99.5,"minimum":99}]}]}]}'
        function Get-Rules([string] $Locations = '[{"name":"westus3","displayName":"West US 3"}]', [string] $Health = '{"properties":{"availabilityState":"Available","summary":"OK"}}') {
            [ordered]@{
                '^account list-locations' = $Locations
                'metrics availability'    = $availability
                'metrics connection_'     = '{}'
                'metrics replication_lag' = ''
                'availabilityStatuses'    = $Health
                'ResourceHealth/events'   = $events
            }
        }
    }

    It 'runs with no LOCALAPPDATA or TEMP (macOS/Linux) and writes its evidence to the temp folder' {
        $tmp = New-TestScratch 'tmp'
        $r = Invoke-Book $s -Az (Get-Rules) -SqlCmd $sqlcmd -Environment @{ LOCALAPPDATA = $null; TEMP = $null; TMP = $tmp; TMPDIR = $tmp }
        $r.ExitCode | Should -Be 0 -Because $r.Text
        $r.Text | Should -Match 'PRIMARY\s+HEALTHY'
        $evidence = Get-ChildItem $tmp -Directory -Filter 'wardgeneral-ch07-availability-*' | Select-Object -First 1
        $evidence | Should -Not -BeNullOrEmpty
        foreach ($f in 'azure-monitor-availability.json', 'resource-health.json', 'service-health.json') {
            Test-Path (Join-Path $evidence.FullName $f) | Should -BeTrue
        }
    }

    It 'tolerates metrics with no value array and a region with no display name' {
        $out = New-TestScratch 'avail'
        $r = Invoke-Book $s "-OutputDirectory '$out'" -Az (Get-Rules -Locations '[{"name":"westus3"}]') -SqlCmd $sqlcmd
        $r.ExitCode | Should -Be 0 -Because $r.Text
        $r.Text | Should -Match 'Region\s+: westus3\s+\(westus3\)'
        $metrics = Get-Content (Join-Path $out 'azure-monitor-availability.json') -Raw | ConvertFrom-Json
        @($metrics.Metrics).Count | Should -Be 1
    }

    It 'counts only Azure SQL Database events in the database region' {
        $out = New-TestScratch 'avail'
        $r = Invoke-Book $s "-OutputDirectory '$out'" -Az (Get-Rules) -SqlCmd $sqlcmd
        $r.Text | Should -Match 'Service Health\s+: 1 Azure SQL Database event\(s\) in West US 3 .*\(3 subscription event\(s\) checked\)'
        $health = Get-Content (Join-Path $out 'service-health.json') -Raw | ConvertFrom-Json
        @($health.MatchingEvents).TrackingId | Should -Be 'match'
    }

    It 'reports unavailable Resource Health without failing' {
        $out = New-TestScratch 'avail'
        $r = Invoke-Book $s "-OutputDirectory '$out'" -Az (Get-Rules -Health 'EXIT:1|') -SqlCmd $sqlcmd
        $r.ExitCode | Should -Be 0 -Because $r.Text
        $r.Text | Should -Match 'Resource Health : unavailable'
    }

    It 'stops when the replica query fails' {
        $r = Invoke-Book $s "-OutputDirectory '$(New-TestScratch 'avail')'" -Az (Get-Rules) -SqlCmd (New-FakeSqlCmd -ExitCode 1)
        $r.ExitCode | Should -Not -Be 0
        $r.Text | Should -Match 'sqlcmd(\.exe)?"? (exited with|ended with non-zero exit) code:? 1'
        $r.Text | Should -Not -Match 'Azure Monitor availability evidence'
    }

    It 'makes only read-only Azure calls' {
        $r = Invoke-Book $s "-OutputDirectory '$(New-TestScratch 'avail')'" -Az (Get-Rules) -SqlCmd $sqlcmd
        $r.AzCalls | Where-Object { $_ -match '^rest ' } | ForEach-Object { $_ | Should -Match '^rest --method get ' }
        $r.AzCalls -join "`n" | Should -Not -Match '(^|\n)\S+( \S+)* (create|update|delete|set)( |$)'
    }
}

Describe 'Resource Graph lookup with one subscription (Chapter 7)' -Tag 'Offline' {
    It 'sends subscriptions as a JSON array from <_>' -ForEach @(
        'examples/ch07-observability/engineevents/azuresqlerrors/azuresqlerrors.ps1'
    ) {
        $capture = Join-Path (New-TestScratch 'arg') 'body.json'
        $prelude = @"
function global:Invoke-RestMethod {
    param(`$Method, `$Uri, `$Headers, `$ContentType, `$Body)
    if (`$Uri -match 'ResourceGraph') { Set-Content -LiteralPath '$capture' -Value `$Body; throw 'BOOKTEST captured' }
}
"@
        $r = Invoke-Book $_ -Prelude $prelude -Az ([ordered]@{ '^account list' = '00000000-0000-0000-0000-000000000001' })
        $r.Text | Should -Match 'BOOKTEST captured'
        $body = Get-Content $capture -Raw
        $body | Should -Match '"subscriptions":\s*\[\s*"00000000-0000-0000-0000-000000000001"\s*\]'
    }
}

Describe 'Local port helpers (Chapters 4 and 8)' -Tag 'Offline' {
    BeforeAll {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
        $listener.Start()
        $port = $listener.LocalEndpoint.Port
    }
    AfterAll { $listener.Stop() }

    It 'finds this process listening on a port, and its command line, in <_>' -ForEach @(
        'examples/ch04-first-app/shutdown.ps1',
        'examples/ch08-security/rls/stop-local-apps.ps1',
        'examples/ch08-security/rls/00-inspect-rls-state.ps1'
    ) {
        $ast = Get-ScriptAst (Get-BookPath $_)
        $functions = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $n.Name -in 'Get-PortOwnerId', 'Get-ProcessCommandLine' }, $true)
        @($functions).Count | Should -BeGreaterThan 0
        foreach ($f in $functions) { . ([scriptblock]::Create($f.Extent.Text)) }
        @(Get-PortOwnerId $port) | Should -Contain $PID
        if ($functions.Name -contains 'Get-ProcessCommandLine') {
            Get-ProcessCommandLine $PID | Should -Match '(?i)pwsh|powershell'
        }
    }
}

Describe 'check-ai-env.ps1 (Chapter 5)' -Tag 'Offline' {
    BeforeAll {
        $s = 'examples/ch05-ai-ready-sql/check-ai-env.ps1'
        function Invoke-Check([System.Collections.IDictionary] $Extra = [ordered]@{}, [hashtable] $Environment = @{}, [switch] $WithGateway) {
            $file = Join-Path (New-TestScratch 'ch05') 'ch05.env'
            @('RG=rg-collierhealth', 'SRV=collierhealth-test', 'AI_RESOURCE=collierhealth-ai',
                'WardGeneral__Server=collierhealth-test.database.windows.net', 'WardGeneral__Database=wardgeneral') | Set-Content $file
            $rules = [ordered]@{}
            foreach ($k in $Extra.Keys) { $rules[$k] = $Extra[$k] }
            foreach ($pair in @(
                    @('^group show', 'rg-collierhealth'),
                    @('^sql server show .*identity.principalId', 'principal-1'),
                    @('^sql server show .*location', 'westus3'),
                    @('^sql server show', 'collierhealth-test'),
                    @('^sql db show -n wardgeneral-research', 'wardgeneral-research'),
                    @('^sql db show -n wardgeneral ', 'wardgeneral'),
                    @('^cognitiveservices account show', 'EXIT:3|'),
                    @('checkDomainAvailability', '{"isSubdomainAvailable":true}')
                )) { if (-not $rules.Contains($pair[0])) { $rules[$pair[0]] = $pair[1] } }
            $env = @{ AI_LOCATION = $null; GATEWAY_LOCATION = $null; APIM_NAME = $null; CS_RESOURCE = $null; SUBSCRIPTION_ID = $null; CS_SKU = $null; PUBLISHER_EMAIL = 'a@example.com' }
            foreach ($k in $Environment.Keys) { $env[$k] = $Environment[$k] }
            $gateway = if ($WithGateway) { '' } else { '-NoGateway ' }
            Invoke-Book $s "$gateway-Path '$file'" -Az $rules -Environment $env
        }
    }

    It 'stops when the subscription''s one free Content Safety account is in use' {
        $r = Invoke-Check -WithGateway -Extra ([ordered]@{
                '^cognitiveservices account list --query' = "collierhealth-contentsafety`trg-collierhealth`tF0"
                '^apim show'                              = ''
            })
        $r.ExitCode | Should -Be 1
        $r.Text | Should -Match 'Content Safety\s+collierhealth-ai-contentsafety\s+FREE TIER IN USE'
        $r.Text | Should -Match "'collierhealth-contentsafety' in resource group 'rg-collierhealth'"
        $r.Text | Should -Match 'Set CS_SKU=S0'
    }

    It 'plans an S0 Content Safety account when CS_SKU=S0, even with the free tier in use' {
        $r = Invoke-Check -WithGateway -Environment @{ CS_SKU = 'S0' } -Extra ([ordered]@{
                '^cognitiveservices account list --query' = "collierhealth-contentsafety`trg-collierhealth`tF0"
                '^apim show'                              = ''
            })
        $r.ExitCode | Should -Be 0 -Because $r.Text
        $r.Text | Should -Match 'Content Safety\s+collierhealth-ai-contentsafety\s+WILL BE CREATED \(S0\)'
    }

    It 'plans a new Foundry account in the SQL server''s region by default' {
        $r = Invoke-Check
        $r.ExitCode | Should -Be 0 -Because $r.Text
        $r.Text | Should -Match 'Foundry account\s+collierhealth-ai\s+WILL BE CREATED'
        $r.Text | Should -Match "Foundry in westus3 \(the SQL server's region\)"
    }

    It 'honors AI_LOCATION' {
        $r = Invoke-Check -Environment @{ AI_LOCATION = 'eastus2' }
        $r.Text | Should -Match 'Foundry in eastus2'
        $r.Text | Should -Not -Match "the SQL server's region"
    }

    It 'stops when the Foundry name is taken elsewhere in Azure' {
        $r = Invoke-Check -Extra ([ordered]@{ 'checkDomainAvailability' = '{"isSubdomainAvailable":false,"reason":"Subdomain is in use"}' })
        $r.ExitCode | Should -Be 1
        $r.Text | Should -Match 'NAME NOT AVAILABLE'
        $r.Text | Should -Match 'Choose a different AI_RESOURCE'
    }

    It 'stops when a Chapter 2 prerequisite is missing' {
        $r = Invoke-Check -Extra ([ordered]@{ '^sql db show -n wardgeneral ' = '' })
        $r.ExitCode | Should -Be 1
        $r.Text | Should -Match 'belong to Chapter 2'
    }

    It 'makes no change: its only POST is the name-availability check' {
        $r = Invoke-Check
        $posts = @($r.AzCalls | Where-Object { $_ -match '--method (post|put|patch|delete)' })
        $posts.Count | Should -Be 1
        $posts[0] | Should -Match 'checkDomainAvailability'
        $r.AzCalls -join "`n" | Should -Not -Match '(^|\n)\S+( \S+)* (create|update|delete)( |$)'
    }
}

Describe 'add-content-safety.ps1 (Chapter 5)' -Tag 'Offline' {
    BeforeAll {
        $s = 'examples/ch05-ai-ready-sql/add-content-safety.ps1'
        $args5 = '-ResourceGroup rg-collierhealth-test -ApimName collierhealth-test-ai-gateway -CsResourceName collierhealth-test-ai-contentsafety -SqlServerName collierhealth-test -SubscriptionId 00000000-0000-0000-0000-000000000000'
        $rules = [ordered]@{
            '^cognitiveservices account show .*--query name' = ''
            '^cognitiveservices account list'                = '[{"name":"collierhealth-contentsafety","resourceGroup":"rg-collierhealth","sku":"F0"}]'
        }
    }

    It 'stops before creating anything when the free tier is already in use' {
        $r = Invoke-Book $s $args5 -Az $rules -Environment @{ CS_SKU = $null }
        $r.ExitCode | Should -Be 1
        $r.Text | Should -Match "one free \(F0\) Content Safety account is already in use: 'collierhealth-contentsafety' in resource group 'rg-collierhealth'"
        $r.Text | Should -Match 'set CS_SKU=S0'
        $r.AzCalls -join "`n" | Should -Not -Match 'account create'
    }

    It 'creates an S0 account when CS_SKU=S0' {
        $r = Invoke-Book $s $args5 -Az $rules -Environment @{ CS_SKU = 'S0' }
        @($r.AzCalls | Where-Object { $_ -match '^cognitiveservices account create' }) | Should -HaveCount 1
        ($r.AzCalls | Where-Object { $_ -match '^cognitiveservices account create' }) | Should -Match '--sku S0'
    }

    It 'shows the Azure CLI''s reason when the create fails' {
        $failing = [ordered]@{
            '^cognitiveservices account show .*--query name' = ''
            '^cognitiveservices account list'                = '[]'
            '^cognitiveservices account create'              = 'EXIT:1|'
        }
        $r = Invoke-Book $s $args5 -Az $failing -Environment @{ CS_SKU = $null }
        $r.ExitCode | Should -Be 1
        $r.Text | Should -Match 'ERROR creating Content Safety resource:'
        $r.Text | Should -Match 'fake az exit 1'
    }
}
Describe 'query-audit.ps1 (Chapter 8)' -Tag 'Offline' {
    BeforeAll {
        $s = 'examples/ch08-security/auditing/query-audit.ps1'
        $rules = [ordered]@{
            '^monitor log-analytics workspace list' = '{"id":"/w","name":"wardgeneral-ch08-audit","customerId":"c","tags":{"hyperscalebook":"ch08-auditing"}}'
        }
        function New-RestFailure([string] $Body) {
            @"
function global:Invoke-RestMethod {
    `$record = [Management.Automation.ErrorRecord]::new([Exception]::new('Response status code does not indicate success: 400 (Bad Request).'), 'HttpError', 'InvalidOperation', `$null)
    `$record.ErrorDetails = [Management.Automation.ErrorDetails]::new('$($Body.Replace("'", "''"))')
    throw `$record
}
"@
        }
        $window = "-StartUtc '2026-01-01T00:00:00Z' -EndUtc '2026-01-01T01:00:00Z'"
    }

    It 'explains a new workspace that has no audit columns yet, instead of failing with 400' {
        $body = '{"error":{"code":"BadArgumentError","innererror":{"code":"SemanticError","innererror":{"code":"SEM0100","message":"''where'' operator: Failed to resolve column or scalar expression named ''event_time_t''"}}}}'
        $r = Invoke-Book $s $window -Az $rules -Prelude (New-RestFailure $body)
        $r.ExitCode | Should -Be 0 -Because $r.Text
        $r.Text | Should -Match "No audit records have reached workspace 'wardgeneral-ch08-audit' yet"
        $r.Text | Should -Match 'up to 90 minutes'
    }

    It 'shows Log Analytics'' reason for any other rejected query' {
        $r = Invoke-Book $s $window -Az $rules -Prelude (New-RestFailure '{"error":{"code":"BadArgumentError","message":"Syntax error"}}')
        $r.ExitCode | Should -Not -Be 0
        $r.Text | Should -Match 'Log Analytics rejected the audit query: .*Syntax error'
    }
}
Describe 'sqlsim workloads (Chapter 10)' -Tag 'Offline' {
    It '<_> gives each sign-in more than the driver''s 15-second default' -ForEach @(
        'examples/ch10-performance/01-scale-compute/run-workload.ps1',
        'examples/ch10-performance/02-grow-data/run-demo.ps1'
    ) {
        # Hundreds of simultaneous token sign-ins from a laptop overran 15 s in live runs.
        $text = Get-Content -LiteralPath (Get-BookPath $_) -Raw
        $match = [regex]::Match($text, '(?:-l\s+[''"]?|''-l'',\s*'')(\d+)')
        $match.Success | Should -BeTrue -Because 'sqlsim must be given an explicit login timeout (-l)'
        [int]$match.Groups[1].Value | Should -BeGreaterOrEqual 60
    }
}