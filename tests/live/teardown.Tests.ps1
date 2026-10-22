#requires -Version 7.0
# Live tier - teardown. Removes only what the suite created: the resource group
# must carry the booktest=true tag that the suite adds at creation.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'lib' 'BookTest.psm1') -Force
    $ctx = Get-BookLiveContext
    $script:rg = Invoke-BookAz group show --name $ctx.ResourceGroup
    $script:owned = Test-BookTestTag $script:rg
}

Describe 'Teardown' -Tag 'Teardown' {
    It 'refuses to touch a resource group the suite did not create' {
        if (-not $script:rg) { Set-ItResult -Skipped -Because "$($ctx.ResourceGroup) does not exist" }
        $script:owned | Should -BeTrue -Because 'only a group tagged booktest=true is deleted'
    }

    It 'drops the Chapter 5 database objects (reset-ai-objects.sql)' {
        if (-not $script:owned -or -not $ctx.AiResource) { Set-ItResult -Skipped -Because 'no test environment or no AI resource' }
        if (-not (Invoke-BookAz sql db show --resource-group $ctx.ResourceGroup --server $ctx.Server --name $ctx.Database)) {
            Set-ItResult -Skipped -Because 'the database does not exist'
        }
        $apimToken = if ($ctx.NoGateway) { 'no-gateway' } else { $ctx.Apim }
        $sql = Copy-BookSql -File 'examples/ch05-ai-ready-sql/reset-ai-objects.sql' -Name 'teardown/sql/reset-ai-objects.sql' `
            -Replace ([ordered]@{ '<your-foundry>' = $ctx.AiResource; '<your-apim>' = $apimToken })
        $null = Invoke-BookSql -File $sql -Name 'teardown/reset-ai-objects'
    }

    It 'removes and purges the Azure AI resources (reset-ai-azure.ps1)' {
        if (-not $script:owned -or -not $ctx.AiResource) { Set-ItResult -Skipped -Because 'no test environment or no AI resource' }
        $r = Invoke-BookScript -Script 'examples/ch05-ai-ready-sql/reset-ai-azure.ps1' -Arguments '-Confirm:$false' -Name 'teardown/reset-ai-azure' -TimeoutMinutes 90
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }

    It 'deletes the test resource group' {
        if (-not $script:owned) { Set-ItResult -Skipped -Because 'nothing the suite owns is left' }
        & az group delete --name $ctx.ResourceGroup --yes 2>&1 | Out-File (Get-BookEvidencePath 'teardown/group-delete.log')
        (& az group exists --name $ctx.ResourceGroup) | Should -Be 'false'
    }

    It 'reports the Key Vault left in soft-delete' {
        $vault = Get-BookState 'TdeVault'
        if (-not $vault) { Set-ItResult -Skipped -Because 'Chapter 8 TDE did not run' }
        Write-Host "      Key Vault '$vault' is soft-deleted with purge protection; Azure removes it when retention ends. It does not bill." -ForegroundColor Yellow
    }
}
