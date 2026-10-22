#requires -Version 7.0
# Live tier - Chapter 5: Azure AI resources, embeddings, vector search, and the
# AI-enabled app. Uses temp copies of the SQL with the reader's placeholders
# replaced; the repository files are never edited.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'lib' 'BookTest.psm1') -Force
    $ctx = Get-BookLiveContext
    $ch = 'examples/ch05-ai-ready-sql'
    $app = 'examples/ch04-first-app'
    $null = Assert-BookDatabase
    $gatewayArg = if ($ctx.NoGateway) { '-NoGateway' } else { '' }
    $apimToken = if ($ctx.NoGateway) { 'no-gateway' } else { $ctx.Apim }
    $script:encounterId = Get-BookState 'EncounterId'
    if (-not $script:encounterId) {
        $script:encounterId = Get-BookScalar -Name 'ch05/active-encounter' `
            -Query "SELECT TOP (1) EncounterId FROM clinical.Encounter WHERE Status = N'Active' ORDER BY EncounterId"
    }
}

Describe 'Chapter 5 - Azure AI resources' -Tag 'Ch05' {
    It 'reports what it would create (check-ai-env.ps1)' {
        $r = Invoke-BookScript -Script "$ch/check-ai-env.ps1" -Arguments $gatewayArg -Name 'ch05/check-ai-env-before' -TimeoutMinutes 10
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }

    It 'deploys Foundry, the models, identity, and RBAC (deploy-ai.ps1)' {
        $r = Invoke-BookScript -Script "$ch/deploy-ai.ps1" -Arguments $gatewayArg -Name 'ch05/deploy-ai' -TimeoutMinutes 120
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        Invoke-BookAz cognitiveservices account show --resource-group $ctx.ResourceGroup --name $ctx.AiResource |
            Should -Not -BeNullOrEmpty
        if (-not $ctx.NoGateway) {
            Invoke-BookAz apim show --resource-group $ctx.ResourceGroup --name $ctx.Apim | Should -Not -BeNullOrEmpty
        }
    }

    It 'reports the deployed resources (check-ai-env.ps1)' {
        $r = Invoke-BookScript -Script "$ch/check-ai-env.ps1" -Arguments $gatewayArg -Name 'ch05/check-ai-env-after' -TimeoutMinutes 10
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }

    It 'previews the teardown without changing anything (reset-ai-azure.ps1 -WhatIf)' {
        $r = Invoke-BookScript -Script "$ch/reset-ai-azure.ps1" -Arguments '-WhatIf' -Name 'ch05/reset-ai-azure-whatif' -TimeoutMinutes 10
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        Invoke-BookAz cognitiveservices account show --resource-group $ctx.ResourceGroup --name $ctx.AiResource |
            Should -Not -BeNullOrEmpty
    }
}

Describe 'Chapter 5 - AI in the database' -Tag 'Ch05' {
    It 'creates the external model and embeds clinical notes (06-ai-embeddings.sql)' {
        $replace = [ordered]@{ '<your-foundry>' = $ctx.AiResource }
        if ($ctx.EmbeddingLimit -gt 0) {
            # Bounded subset: the same loop, stopped after the first batches.
            $replace['WHILE @Rows > 0'] = "WHILE @Rows > 0 AND @Total < $($ctx.EmbeddingLimit)"
        }
        $sql = Copy-BookSql -File "$ch/06-ai-embeddings.sql" -Replace $replace -Name 'ch05/sql/06-ai-embeddings.sql'
        $minutes = if ($ctx.EmbeddingLimit -gt 0) { 60 } else { 360 }
        $r = Invoke-BookSql -File $sql -Name 'ch05/06-ai-embeddings' -TimeoutMinutes $minutes
        $r.Text | Should -Match '06-ai-embeddings\.sql complete'
    }

    It 'has embeddings (verify-embeddings.sql)' {
        $r = Invoke-BookSql -File "$ch/verify-embeddings.sql" -Name 'ch05/verify-embeddings'
        $embedded = [int](Get-BookValue -Text ($r.Text -replace '\s{2,}', "`n") -Key 'EMBEDDED')
        $embedded | Should -BeGreaterThan 0
        if ($ctx.EmbeddingLimit -eq 0) {
            [int](Get-BookValue -Text ($r.Text -replace '\s{2,}', "`n") -Key 'MISSING') | Should -Be 0
        }
    }

    It 'builds the DiskANN index (07-vector-index.sql)' {
        $null = Invoke-BookSql -File "$ch/07-vector-index.sql" -Name 'ch05/07-vector-index' -TimeoutMinutes 60
    }

    It 'creates clinical.GenerateClinicalAssistance (08-ai-assistance.sql)' {
        $sql = Copy-BookSql -File "$ch/08-ai-assistance.sql" -Name 'ch05/sql/08-ai-assistance.sql' `
            -Replace ([ordered]@{ '<your-foundry>' = $ctx.AiResource; '<your-apim>' = $apimToken })
        $null = Invoke-BookSql -File $sql -Name 'ch05/08-ai-assistance'
    }

    It 'generates clinical assistance for an active encounter' {
        $useGateway = if ($ctx.NoGateway) { 0 } else { 1 }
        $r = Invoke-BookSql -Name 'ch05/generate-clinical-assistance' -TimeoutMinutes 10 `
            -Query "EXEC clinical.GenerateClinicalAssistance @EncounterId = $($script:encounterId), @UseGateway = $useGateway;"
        $r.Text.Trim() | Should -Not -BeNullOrEmpty
    }

    It 'creates clinical.SearchSimilarNotes (09-research-vector-search.sql)' {
        $null = Invoke-BookSql -File "$ch/09-research-vector-search.sql" -Name 'ch05/09-research-vector-search'
    }

    It 'searches similar notes on the named replica' {
        $r = Invoke-BookSql -Database $ctx.NamedReplica -Name 'ch05/search-similar-notes-named' -TimeoutMinutes 10 `
            -Query "EXEC clinical.SearchSimilarNotes @QueryText = N'shortness of breath after surgery', @NoteType = NULL;"
        $r.ExitCode | Should -Be 0
    }

    It 'proves the DiskANN index is updateable (10-updateable-index-proof.sql)' {
        $r = Invoke-BookSql -File "$ch/10-updateable-index-proof.sql" -Name 'ch05/10-updateable-index-proof' -TimeoutMinutes 15
        $r.Text | Should -Match '10-updateable-index-proof\.sql complete'
    }

    It 'shows the gateway blocking prompt injection (11-prompt-injection-proof.sql)' -Tag 'Gateway' {
        if ($ctx.NoGateway) { Set-ItResult -Skipped -Because 'the gateway was not deployed (-NoGateway)' }
        $r = Invoke-BookSql -File "$ch/11-prompt-injection-proof.sql" -Name 'ch05/11-prompt-injection-proof' -TimeoutMinutes 15
        $r.ExitCode | Should -Be 0
        # Grade on the message, not the status code (Chapter 5 README): a 400 from
        # the model's own Prompt Shields means the gateway policy never ran.
        $r.Text | Should -Match 'Request failed content safety check'
    }
}

Describe 'Chapter 5 - the AI-enabled app' -Tag 'Ch05' {
    It 'serves the chart and research pages (run-ai-app.ps1)' {
        $script:aiApp = Start-BookBackground -Script "$ch/run-ai-app.ps1" -Arguments '-NoBrowser' -Name 'ch05/run-ai-app'
        Wait-BookCondition -Because 'run-ai-app.ps1 to serve /healthz' -TimeoutSeconds 420 -IntervalSeconds 10 -Condition {
            Get-BookHttp "$($ctx.AppUrl)/healthz" -TimeoutSeconds 5
        } | Should -Not -BeNullOrEmpty
        (Get-BookHttp "$($ctx.AppUrl)/chart/$($script:encounterId)" -TimeoutSeconds 120).StatusCode | Should -Be 200
        (Get-BookHttp "$($ctx.AppUrl)/research" -TimeoutSeconds 120).StatusCode | Should -Be 200
    }

    AfterAll {
        $null = Invoke-BookScript -Script "$app/shutdown.ps1" -Arguments '-Confirm:$false' -Name 'ch05/shutdown' -TimeoutMinutes 5
        Stop-BookBackground $script:aiApp
    }
}
