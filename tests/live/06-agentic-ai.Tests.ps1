#requires -Version 7.0
# Live tier - Chapter 6: SQL MCP Server (DAB) and the agent.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'lib' 'BookTest.psm1') -Force
    $ctx = Get-BookLiveContext
    $ch = 'examples/ch06-agentic-ai'
    $app = 'examples/ch04-first-app'
    $null = Assert-BookDatabase

    function Stop-Chapter6Apps([string] $Name) {
        $null = Invoke-BookScript -Script "$app/shutdown.ps1" -Arguments '-Confirm:$false' -Name "ch06/$Name-shutdown" -TimeoutMinutes 5
        $null = Invoke-BookScript -Script 'examples/ch08-security/rls/stop-local-apps.ps1' -Arguments '-Confirm:$false' -Name "ch06/$Name-stop-local-apps" -TimeoutMinutes 5
    }
}

Describe 'Chapter 6 - model access and SQL MCP Server' -Tag 'Ch06' {
    It 'reports model access (grant-model-access.ps1)' {
        $r = Invoke-BookScript -Script "$ch/grant-model-access.ps1" -Name 'ch06/grant-model-access-report' -TimeoutMinutes 10
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }

    It 'grants model access to the signed-in user (grant-model-access.ps1 -Apply)' {
        $r = Invoke-BookScript -Script "$ch/grant-model-access.ps1" -Arguments '-Apply' -Name 'ch06/grant-model-access-apply' -TimeoutMinutes 10
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }

    It 'deploys the agent contracts and DAB config (setup-dab.ps1)' {
        $r = Invoke-BookScript -Script "$ch/setup-dab.ps1" -Name 'ch06/setup-dab' -TimeoutMinutes 20
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
    }

    It 'serves seven MCP tools (run-dab.ps1 + probe-mcp.ps1)' {
        $script:dab = Start-BookBackground -Script "$ch/run-dab.ps1" -Name 'ch06/run-dab'
        Wait-BookCondition -Because 'SQL MCP Server to answer on port 5000' -TimeoutSeconds 240 -IntervalSeconds 10 -Condition {
            (Invoke-BookScript -Script "$ch/probe-mcp.ps1" -Arguments '-Quiet' -Name 'ch06/probe-mcp-quiet' -TimeoutMinutes 2).ExitCode -eq 0
        } | Should -BeTrue
        $r = Invoke-BookScript -Script "$ch/probe-mcp.ps1" -Name 'ch06/probe-mcp' -TimeoutMinutes 2
        $r.Text | Should -Match '\b7 tools\b'
    }

    AfterAll {
        Stop-BookBackground $script:dab
        Stop-Chapter6Apps 'run-dab'
    }
}

Describe 'Chapter 6 - the app with the agent' -Tag 'Ch06' {
    It 'starts DAB and the app together (start-demo.ps1 -Enable AiAssistance,AiAgent)' {
        $r = Invoke-BookScript -Script "$app/start-demo.ps1" -Arguments '-NoBrowser -SkipFirewall -Enable AiAssistance,AiAgent' -Name 'ch06/start-demo-agent' -TimeoutMinutes 15
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        (Get-BookHttp "$($ctx.AppUrl)/healthz").StatusCode | Should -Be 200
        (Invoke-BookScript -Script "$ch/probe-mcp.ps1" -Arguments '-Quiet' -Name 'ch06/probe-mcp-demo' -TimeoutMinutes 2).ExitCode | Should -Be 0
    }

    It 'refreshes the shift window and restarts (refresh-and-run.ps1 -Detached)' {
        Stop-Chapter6Apps 'before-refresh'
        $r = Invoke-BookScript -Script "$ch/refresh-and-run.ps1" -Arguments '-Detached -NoBrowser -SkipFirewall' -Name 'ch06/refresh-and-run' -TimeoutMinutes 15
        $r.ExitCode | Should -Be 0 -Because $r.LogPath
        (Get-BookHttp "$($ctx.AppUrl)/healthz").StatusCode | Should -Be 200
    }

    AfterAll { Stop-Chapter6Apps 'agent' }
}
