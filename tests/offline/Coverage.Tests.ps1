#requires -Version 7.0
# Offline tier - coverage guard. Every example script must be run by the live
# tier, directly or through the script that calls it (fixtures/covered-via.json).
# Adding an example without a live test fails here.

BeforeDiscovery {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:examples = Get-ChildItem (Join-Path $root 'examples') -Recurse -Include *.ps1, *.sql |
        Where-Object { $_.FullName -notmatch '[\\/](bin|obj|_local|results)[\\/]' } |
        ForEach-Object { @{ Rel = $_.FullName.Substring($root.Length + 1) -replace '\\', '/' } }
    $via = (Get-Content (Join-Path $PSScriptRoot '..' 'fixtures' 'covered-via.json') -Raw | ConvertFrom-Json).coveredVia
    $script:via = $via.PSObject.Properties | ForEach-Object { @{ Child = $_.Name; Parent = $_.Value } }
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'lib' 'BookTest.psm1') -Force
    $root = Get-BookRepoRoot
    $via = @{}
    (Get-Content (Join-Path $PSScriptRoot '..' 'fixtures' 'covered-via.json') -Raw | ConvertFrom-Json).coveredVia.PSObject.Properties |
        ForEach-Object { $via[$_.Name] = $_.Value }

    # Live test text keyed by the chapter folders each file names in a variable.
    $live = foreach ($file in Get-ChildItem (Join-Path $root 'tests' 'live') -Filter *.Tests.ps1) {
        $text = Get-Content -LiteralPath $file.FullName -Raw
        [pscustomobject]@{
            Text     = $text
            Chapters = @([regex]::Matches($text, '[''"](examples/[\w-]+)[''"/]') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
        }
    }

    function Test-DirectlyCovered([string] $Rel) {
        $chapter = ($Rel -split '/')[0..1] -join '/'
        $inChapter = $Rel.Substring($chapter.Length + 1)
        foreach ($l in $live) {
            if ($l.Chapters -contains $chapter -and ($l.Text.Contains("/$inChapter") -or $l.Text.Contains("'$inChapter'"))) { return $true }
        }
        $false
    }

    function Test-Covered([string] $Rel, [int] $Depth = 0) {
        if ($Depth -gt 10) { return $false }
        if (Test-DirectlyCovered $Rel) { return $true }
        if ($via.ContainsKey($Rel)) { return Test-Covered $via[$Rel] ($Depth + 1) }
        $false
    }
}

Describe 'Live-tier coverage' -Tag 'Offline' {
    It '<Rel> is exercised by the live tier' -ForEach $script:examples {
        Test-Covered $Rel | Should -BeTrue -Because 'add a live test for it, or list the script that calls it in tests/fixtures/covered-via.json'
    }

    It '<Parent> really calls <Child>' -ForEach $script:via {
        Test-Path -LiteralPath (Join-Path $root $Child) | Should -BeTrue -Because 'covered-via.json must not list a script that no longer exists'
        $parentText = Get-Content -LiteralPath (Join-Path $root $Parent) -Raw
        $parentText.Contains((Split-Path $Child -Leaf)) | Should -BeTrue -Because "$Parent must invoke $Child for the mapping to mean anything"
    }
}
