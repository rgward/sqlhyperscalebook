#requires -Version 7.0
# Offline tier - the Copilot skills, the book's prompts, and the book's links.

BeforeDiscovery {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:skills = Get-ChildItem (Join-Path $root '.github' 'skills') -Directory |
        ForEach-Object { @{ Name = $_.Name; Path = (Join-Path $_.FullName 'SKILL.md') } }
    $script:prompts = (Get-Content (Join-Path $PSScriptRoot '..' 'fixtures' 'book-prompts.json') -Raw | ConvertFrom-Json).prompts |
        ForEach-Object { @{ Chapter = $_.chapter; Skill = $_.skill; Readme = $_.readme; Prompt = $_.prompt } }
    $links = (Get-Content (Join-Path $PSScriptRoot '..' 'fixtures' 'book-links.json') -Raw | ConvertFrom-Json).chapters
    $script:links = foreach ($ch in $links.PSObject.Properties) {
        foreach ($l in $ch.Value) { @{ Chapter = $ch.Name; Title = $l.title; Url = $l.url } }
    }
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'lib' 'BookTest.psm1') -Force
    $root = Get-BookRepoRoot

    function Get-SkillFrontMatter([string] $Path) {
        $text = Get-Content -LiteralPath $Path -Raw
        $m = [regex]::Match($text, '(?s)\A---\r?\n(.*?)\r?\n---')
        if (-not $m.Success) { return $null }
        $fm = $m.Groups[1].Value
        $name = [regex]::Match($fm, '(?m)^name:\s*(.+)$').Groups[1].Value.Trim().Trim('"', "'")
        $descMatch = [regex]::Match($fm, '(?ms)^description:\s*(.*?)(?=^\w[\w-]*:|\z)')
        $desc = $descMatch.Groups[1].Value -replace '^\s*[>|][-+]?\s*', '' -replace '\s+', ' '
        [pscustomobject]@{ Name = $name; Description = $desc.Trim().Trim("'", '"').Replace("''", "'"); Body = $text.Substring($m.Length) }
    }

    function ConvertTo-Comparable([string] $Text) {
        $plain = $Text -replace '(?m)^\s*>\s?', '' -replace '[*_`]', ''
        ($plain -replace '[\u2018\u2019]', "'" -replace '[\u201C\u201D]', '"' -replace '\s+', ' ').Trim().ToLowerInvariant()
    }

    $readmeText = @{}
    Get-ChildItem (Join-Path $root 'examples') -Recurse -Filter README.md | ForEach-Object { $readmeText[$_.FullName] = Get-Content $_.FullName -Raw }
    $allReadmes = ($readmeText.Values + (Get-Content (Join-Path $root 'README.md') -Raw)) -join "`n"
}

Describe 'Copilot skills' -Tag 'Offline' {
    It '<Name> has valid front matter' -ForEach $script:skills {
        $fm = Get-SkillFrontMatter $Path
        $fm | Should -Not -BeNullOrEmpty -Because 'SKILL.md must open with --- front matter ---'
        $fm.Name | Should -Be $Name
        $fm.Description.Length | Should -BeGreaterThan 40
    }

    It '<Name> has a description Copilot will load (at most 1,024 characters)' -ForEach $script:skills {
        # Over the Agent Skills limit, Copilot drops the skill without any warning
        # (github/copilot-cli#3494). Five skills, including Chapter 2's, were lost this way.
        (Get-SkillFrontMatter $Path).Description.Length | Should -BeLessOrEqual 1024
    }

    It 'every skill loads in GitHub Copilot CLI (copilot skill list)' {
        # Catches any loader rejection, not only length. Free: no model call.
        if (-not (Get-Command copilot -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'GitHub Copilot CLI is not installed'
            return
        }
        Push-Location $root
        try { $listed = @(copilot skill list --json 2>$null | Out-String | ConvertFrom-Json) }
        finally { Pop-Location }
        $loaded = @($listed | Where-Object { $_.source -eq 'project' } | ForEach-Object name)
        $missing = @(Get-ChildItem (Join-Path $root '.github' 'skills') -Directory | ForEach-Object Name | Where-Object { $_ -notin $loaded })
        $missing | Should -BeNullOrEmpty -Because 'Copilot drops a skill it cannot load, so its book prompts never route'
    }

    It '<Name> refers only to repository files that exist' -ForEach $script:skills {
        $text = Get-Content -LiteralPath $Path -Raw
        $paths = [regex]::Matches($text, '(?<![\w/.-])((?:examples|tools|tests|figures)/[\w./-]+\.(?:ps1|sql|md|json|slnx|csproj|svg|png))') |
            ForEach-Object { $_.Groups[1].Value.TrimEnd('.') } | Select-Object -Unique
        foreach ($p in $paths) {
            # Files the reader creates (ch04.env, appsettings.Development.json) are git-ignored, not shipped.
            & git -C $root check-ignore -q --no-index -- $p
            if ($LASTEXITCODE -eq 0) { continue }
            Test-Path -LiteralPath (Join-Path $root $p) | Should -BeTrue -Because "$Name refers to $p"
        }
    }
}

Describe 'Prompts printed in the book' -Tag 'Offline' {
    It 'Ch <Chapter>: "<Prompt>" reaches <Skill>' -ForEach $script:prompts {
        $skillPath = Join-Path $root '.github' 'skills' $Skill 'SKILL.md'
        Test-Path -LiteralPath $skillPath | Should -BeTrue
        $fm = Get-SkillFrontMatter $skillPath
        # Copilot chooses a skill from its description alone; the body is read only afterwards.
        $haystack = ConvertTo-Comparable $fm.Description
        $needle = ConvertTo-Comparable ($Prompt.TrimEnd('.'))
        $haystack.Contains($needle) | Should -BeTrue -Because "the skill's description must list the book's prompt so Copilot routes it"
    }

    It 'Ch <Chapter>: "<Prompt>" appears in <Readme>' -ForEach $script:prompts {
        $readme = Join-Path $root $Readme
        Test-Path -LiteralPath $readme | Should -BeTrue
        (ConvertTo-Comparable $readmeText[(Resolve-Path $readme).Path]).Contains((ConvertTo-Comparable ($Prompt.TrimEnd('.')))) |
            Should -BeTrue -Because 'readers who skip Copilot read the prompt in the chapter README'
    }
}

Describe 'Links printed in the book' -Tag 'Offline' {
    It '<Chapter>: <Url> is listed in the repository' -ForEach $script:links {
        $allReadmes.Contains($Url.TrimEnd('/')) | Should -BeTrue -Because "'$Title' is printed in the book; the Links from the book lists must carry it"
    }
}

Describe 'Markdown anchors' -Tag 'Offline' {
    It 'every #anchor link resolves to a heading' {
        function Get-Slugs([string] $Path) {
            $seen = @{}
            foreach ($h in Select-String -LiteralPath $Path -Pattern '^#{1,6}\s+(.+?)\s*#*\s*$') {
                $s = $h.Matches[0].Groups[1].Value.ToLowerInvariant() -replace '`', '' -replace '\[([^\]]*)\]\([^)]*\)', '$1' -replace '[^\p{L}\p{N}\s_-]', '' -replace '\s', '-'
                if ($seen.ContainsKey($s)) { $seen[$s]++; $s = "$s-$($seen[$s])" } else { $seen[$s] = 0 }
                $s
            }
            foreach ($a in Select-String -LiteralPath $Path -Pattern '<a\s+(?:name|id)="([^"]+)"' -AllMatches) {
                foreach ($m in $a.Matches) { $m.Groups[1].Value }
            }
        }
        $problems = [Collections.Generic.List[string]]::new()
        $files = Get-ChildItem $root -Recurse -Filter *.md | Where-Object { $_.FullName -notmatch '[\\/](node_modules|bin|obj|\.git|tests[\\/]results)[\\/]' }
        foreach ($file in $files) {
            $text = Get-Content -LiteralPath $file.FullName -Raw
            foreach ($m in [regex]::Matches($text, '\]\((?<path>[^)\s#]*)#(?<anchor>[^)\s]+)\)')) {
                $target = if ($m.Groups['path'].Value) { Join-Path $file.DirectoryName ([uri]::UnescapeDataString($m.Groups['path'].Value)) } else { $file.FullName }
                if ($target -notmatch '\.md$' -or -not (Test-Path -LiteralPath $target)) { continue }
                if ((Get-Slugs $target) -notcontains $m.Groups['anchor'].Value) {
                    $problems.Add("$($file.FullName.Substring($root.Length + 1)): #$($m.Groups['anchor'].Value)")
                }
            }
        }
        $problems | Should -BeNullOrEmpty
    }
}
