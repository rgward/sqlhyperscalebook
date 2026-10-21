#requires -Version 7.0
# Offline tier - repository conventions. No Azure.

BeforeDiscovery {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $examples = Join-Path $root 'examples'
    $script:ps1 = Get-ChildItem $examples -Recurse -Filter *.ps1 |
        Where-Object { $_.FullName -notmatch '[\\/](bin|obj|_local|results)[\\/]' } |
        ForEach-Object { @{ Path = $_.FullName; Name = $_.FullName.Substring($root.Length + 1) } }
    $script:sql = Get-ChildItem $examples -Recurse -Filter *.sql |
        Where-Object { $_.FullName -notmatch '[\\/](bin|obj|_local|results)[\\/]' } |
        ForEach-Object { @{ Path = $_.FullName; Name = $_.FullName.Substring($root.Length + 1) } }
    # Only scripts that create or alter schema objects need the SET preamble (temp tables don't).
    $script:creatingSql = $script:sql | Where-Object {
        (Get-Content -LiteralPath $_.Path -Raw) -match '(?im)^\s*(CREATE|ALTER)\s+(OR\s+ALTER\s+)?(TABLE\s+(?!#)|VIEW|PROCEDURE|PROC|FUNCTION|TRIGGER|(UNIQUE\s+)?(CLUSTERED\s+|NONCLUSTERED\s+)?INDEX|JSON\s+INDEX|VECTOR\s+INDEX)\b'
    }
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'lib' 'BookTest.psm1') -Force
    $root = Get-BookRepoRoot
}

Describe 'Repository validation (tools/validate-repository.ps1)' -Tag 'Offline' {
    It 'passes' {
        $r = Invoke-IsolatedScript -Script 'tools/validate-repository.ps1' -TimeoutSeconds 600
        $r.ExitCode | Should -Be 0 -Because $r.Text
        $r.Text | Should -Match 'Repository checks passed'
    }
}

Describe 'PowerShell scripts' -Tag 'Offline' {
    It '<Name> has no unguarded Windows-only path' -ForEach $script:ps1 {
        $lines = Get-Content -LiteralPath $Path
        $unguarded = @($lines | Where-Object { $_ -match 'Join-Path \(?\$env:LOCALAPPDATA\b(?!\s*\?\?)' -and $_ -notmatch 'if \(\$env:LOCALAPPDATA\)' })
        $unguarded | Should -BeNullOrEmpty -Because 'LOCALAPPDATA does not exist on macOS/Linux; guard it with if ($env:LOCALAPPDATA) or ??'
        @($lines | Where-Object { $_ -match '\$env:TEMP\b' -and $_ -notmatch '^\s*#' }) | Should -BeNullOrEmpty -Because 'use [IO.Path]::GetTempPath()'
    }

    It '<Name> reads no property of a command that may be missing' -ForEach $script:ps1 {
        $text = Get-Content -LiteralPath $Path -Raw
        if ($text -notmatch 'Set-StrictMode') { Set-ItResult -Skipped -Because 'it does not use StrictMode' }
        $text | Should -Not -Match '\(Get-Command [^)|]*-ErrorAction SilentlyContinue\)\.\w+' -Because 'under StrictMode, .Source on a missing command throws; pipe to Select-Object -ExpandProperty Source'
    }

    It '<Name> never hard-codes a secret' -ForEach $script:ps1 {
        $text = Get-Content -LiteralPath $Path -Raw
        $text | Should -Not -Match '(?i)(password|pwd)\s*=\s*[''"][^''"<$\s]{6,}[''"]'
        $text | Should -Not -Match '(?i)AccountKey=[A-Za-z0-9+/]{20,}'
    }
}

Describe 'SQL scripts' -Tag 'Offline' {
    It '<Name> keeps the SET-options preamble' -ForEach $script:creatingSql {
        $text = Get-Content -LiteralPath $Path -Raw
        foreach ($option in 'QUOTED_IDENTIFIER ON', 'ANSI_NULLS ON', 'ARITHABORT ON', 'CONCAT_NULL_YIELDS_NULL ON',
            'ANSI_PADDING ON', 'ANSI_WARNINGS ON', 'NUMERIC_ROUNDABORT OFF') {
            $text | Should -Match "(?i)SET\s+$($option -replace ' ', '\s+')" -Because 'Msg 1934 otherwise; see the root README'
        }
    }

    It '<Name> has no hard-coded server or password' -ForEach $script:sql {
        $text = Get-Content -LiteralPath $Path -Raw
        $text | Should -Not -Match '(?i)collierhealth-\d{3,}\.database\.windows\.net' -Because 'servers come from the reader''s configuration'
        # Demo master-key passwords must look like the placeholders they are.
        $text | Should -Not -Match '(?i)PASSWORD\s*=\s*N?''(?![^'']*Ch[a@]ngeMe)[^''<]{6,}'''
    }
}

Describe 'Reader configuration templates' -Tag 'Offline' {
    It '<_> exists and ships only placeholders' -ForEach @('examples/ch04-first-app/ch04.env.template', 'examples/ch05-ai-ready-sql/ch05.env.template', 'tests/test.env.template') {
        $path = Get-BookPath $_
        Test-Path -LiteralPath $path | Should -BeTrue
        foreach ($line in Get-Content -LiteralPath $path | Where-Object { $_ -match '^\s*[A-Za-z_]+\s*=' }) {
            $value = ($line -split '=', 2)[1].Trim()
            if ($value -match '(?i)password|secret|key') { $value | Should -Match '^<.*>$' }
        }
    }

    It 'git-ignores the files readers and testers fill in' {
        Push-Location (Get-BookRepoRoot)
        try {
            foreach ($f in 'examples/ch04-first-app/ch04.env', 'examples/ch05-ai-ready-sql/ch05.env', 'tests/test.env',
                'tests/results/x.txt', 'tests/.cache/x.txt', 'examples/ch04-first-app/src/WardGeneral.Web/appsettings.Development.json') {
                & git check-ignore -q -- $f
                $LASTEXITCODE | Should -Be 0 -Because "$f must never be committed"
            }
        }
        finally { Pop-Location }
    }
}
