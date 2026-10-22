#requires -Version 7.0
<#
.SYNOPSIS
    Measure whether GitHub Copilot routes each prompt printed in the book to the
    right skill.

.DESCRIPTION
    For every prompt in tests/fixtures/book-prompts.json this runs one
    non-interactive GitHub Copilot CLI session in the repository root and
    records the first skill Copilot loads. The session has only the `skill`
    tool available, so Copilot can choose a skill and nothing else: it cannot
    run shell commands, edit files, or reach Azure.

    It also checks that Copilot loaded every skill under .github/skills. A skill
    whose description breaks the Agent Skills rules (for example, longer than
    1,024 characters) is dropped silently, and none of its prompts can route.

    This is an evaluation, not a deterministic test: the choice depends on the
    model, so results can vary between runs and model versions. Use -Repeat to
    run each prompt several times. Copilot CLI is a stand-in for VS Code agent
    mode; both read the same .github/skills files. Each session uses one
    Copilot premium request.

.PARAMETER Repeat
    Sessions per prompt. Default 1.

.PARAMETER Model
    Copilot model to use. Default: the CLI's default.

.PARAMETER Chapter
    Only the prompts from these chapters.

.PARAMETER ThrottleLimit
    Sessions run at once. Default 4.

.PARAMETER OutputDirectory
    Default: tests/results/routing-<utc>.

.EXAMPLE
    ./tests/Measure-SkillRouting.ps1
    ./tests/Measure-SkillRouting.ps1 -Repeat 3 -Chapter 2,5
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 10)] [int] $Repeat = 1,
    [string] $Model,
    [int[]] $Chapter,
    [ValidateRange(1, 8)] [int] $ThrottleLimit = 4,
    [string] $OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent

if (-not (Get-Command copilot -ErrorAction SilentlyContinue)) {
    throw 'GitHub Copilot CLI (copilot) was not found. Install it with: npm install -g @github/copilot, then sign in by running copilot once.'
}

$prompts = @((Get-Content (Join-Path $PSScriptRoot 'fixtures' 'book-prompts.json') -Raw | ConvertFrom-Json).prompts |
    Where-Object { -not $Chapter -or $_.chapter -in $Chapter })
if ($prompts.Count -eq 0) { throw 'No book prompts match -Chapter.' }
$repoSkills = @(Get-ChildItem (Join-Path $repo '.github' 'skills') -Directory | ForEach-Object Name)

# Which repository skills Copilot loads at all. A skill that breaks the Agent
# Skills rules (for example, a description over 1,024 characters) is dropped
# silently, and none of its prompts can route.
Push-Location $repo
try { $listed = @(copilot skill list --json 2>$null | Out-String | ConvertFrom-Json) }
finally { Pop-Location }
$loadedSkills = @($listed | Where-Object { $_.source -eq 'project' -and $_.enabled } | ForEach-Object name)
$notLoaded = @($repoSkills | Where-Object { $_ -notin $loadedSkills })

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $PSScriptRoot 'results' ('routing-{0}' -f [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory = (Resolve-Path $OutputDirectory).Path

$runs = foreach ($p in $prompts) {
    foreach ($n in 1..$Repeat) {
        [pscustomobject]@{ Chapter = $p.chapter; Expected = $p.skill; Prompt = $p.prompt; Attempt = $n
            Log = Join-Path $OutputDirectory ('ch{0:D2}-{1}-{2}-{3}.jsonl' -f $p.chapter, $p.skill, ([array]::IndexOf($prompts, $p) + 1), $n) }
    }
}

Write-Host "Skill routing: $($prompts.Count) book prompt(s) x $Repeat = $(@($runs).Count) Copilot session(s), $ThrottleLimit at a time." -ForegroundColor Cyan
Write-Host 'Each session can only choose a skill; it cannot run commands or touch Azure. Each uses one premium request.' -ForegroundColor DarkGray

$results = $runs | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
    $run = $_
    $arguments = @('-p', $run.Prompt, '--available-tools=skill', '--allow-all-tools', '--no-ask-user',
        '--disable-builtin-mcps', '--output-format', 'json')
    if ($using:Model) { $arguments += @('--model', $using:Model) }
    Push-Location $using:repo
    try { & copilot @arguments 2>&1 | Set-Content -LiteralPath $run.Log -Encoding utf8NoBOM }
    finally { Pop-Location }

    $chosen = $null; $modelUsed = $null; $sessionError = $null
    foreach ($line in Get-Content -LiteralPath $run.Log) {
        $evt = try { $line | ConvertFrom-Json } catch { $null }
        if (-not $evt -or -not $evt.PSObject.Properties['type']) { continue }
        switch ($evt.type) {
            'tool.execution_start' {
                if (-not $chosen -and $evt.data.toolName -eq 'skill') { $chosen = $evt.data.arguments.skill; $modelUsed = $evt.data.model }
            }
            'session.error' { $sessionError = $evt.data.message }
        }
    }
    [pscustomobject]@{
        Chapter = $run.Chapter; Prompt = $run.Prompt; Attempt = $run.Attempt; Expected = $run.Expected
        Chosen = $chosen ?? '(none)'; Pass = $chosen -eq $run.Expected; Model = $modelUsed
        Error = $sessionError; Log = $run.Log
    }
}
$results = @($results | Sort-Object Chapter, Prompt, Attempt)

$byPrompt = $results | Group-Object Prompt | ForEach-Object {
    $first = $_.Group[0]
    [pscustomobject]@{
        Chapter = $first.Chapter; Prompt = $first.Prompt; Expected = $first.Expected
        Correct = @($_.Group | Where-Object Pass).Count; Runs = $_.Count
        Chosen = (($_.Group | Group-Object Chosen | ForEach-Object { if ($_.Count -gt 1) { "$($_.Name) x$($_.Count)" } else { $_.Name } }) -join ', ')
    }
} | Sort-Object Chapter

$results | Select-Object Chapter, Prompt, Attempt, Expected, Chosen, Pass, Model, Error, Log |
    ConvertTo-Json -Depth 4 | Set-Content (Join-Path $OutputDirectory 'routing-results.json') -Encoding utf8NoBOM

$passed = @($byPrompt | Where-Object { $_.Correct -eq $_.Runs }).Count
$lines = [Collections.Generic.List[string]]::new()
$lines.Add("# Skill routing - $([DateTime]::UtcNow.ToString('u'))")
$lines.Add('')
$lines.Add("Model: $((@($results.Model | Where-Object { $_ } | Select-Object -Unique) -join ', '))  Repeat: $Repeat")
$lines.Add('')
$lines.Add("Skills in .github/skills: $($repoSkills.Count). Loaded by Copilot: $($loadedSkills.Count).$(if ($notLoaded) { ' NOT LOADED: ' + ($notLoaded -join ', ') })")
$lines.Add('')
$lines.Add('| Ch. | Book prompt | Expected skill | Correct | Copilot chose |')
$lines.Add('| :---: | --- | --- | :---: | --- |')
foreach ($b in $byPrompt) {
    $mark = if ($b.Correct -eq $b.Runs) { '✅' } else { '❌' }
    $lines.Add("| $($b.Chapter) | $($b.Prompt) | ``$($b.Expected)`` | $mark $($b.Correct)/$($b.Runs) | $($b.Chosen) |")
}
$lines.Add('')
$lines.Add("Prompts routed correctly in every run: $passed of $(@($byPrompt).Count).")
$lines | Set-Content (Join-Path $OutputDirectory 'summary.md') -Encoding utf8NoBOM

Write-Host ''
$byPrompt | Format-Table Chapter, @{ n = 'Correct'; e = { "$($_.Correct)/$($_.Runs)" } }, Expected, Chosen, Prompt -AutoSize | Out-String -Width 220 | Write-Host
if ($notLoaded) { Write-Host "Skills Copilot did not load: $($notLoaded -join ', ')" -ForegroundColor Red }
$color = if ($passed -eq @($byPrompt).Count -and -not $notLoaded) { 'Green' } else { 'Red' }
Write-Host "Routed correctly in every run: $passed of $(@($byPrompt).Count) prompts. Results: $OutputDirectory" -ForegroundColor $color
exit $(if ($color -eq 'Green') { 0 } else { 1 })
