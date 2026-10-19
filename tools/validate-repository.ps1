#requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$failures = [System.Collections.Generic.List[string]]::new()

Push-Location $root
try {
    $files = @(git -c core.quotepath=false ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to list repository files with git.'
    }
    $files = @($files | Sort-Object -Unique | Where-Object {
        Test-Path -LiteralPath (Join-Path $root $_) -PathType Leaf
    })

    foreach ($file in $files) {
        $path = Join-Path $root $file
        if ($file -match '(^|/)(remove_before_publish|bin|obj|publish|TestResults|\.vscode)(/|$)' -or
            $file -match '^examples/ch10-performance/.*/results/' -or
            $file -match '(^|/)appsettings\.Development\.json$' -or
            $file -match '\.env$|\.env\.local$|(^|/)\.env\.(?!template$|example$)' -or
            $file -match '\.(code-workspace|pem|key|pfx|p12|exe|com|msi|msix|appx|dll|so|dylib|a|lib|pdb|nupkg|jar|class|zip|7z|rar|tar|tgz|gz|bz2|xz|trx|log)$' -or
            $file -match '\.(so|tar)\.') {
            $failures.Add("${file}: local configuration, generated output, binary, or author-only file must not be published.")
        }

        switch ([IO.Path]::GetExtension($file)) {
            '.ps1' {
                $tokens = $null
                $parseErrors = $null
                $null = [System.Management.Automation.Language.Parser]::ParseFile(
                    $path, [ref]$tokens, [ref]$parseErrors)
                foreach ($parseError in $parseErrors) {
                    $failures.Add("${file}:$($parseError.Extent.StartLineNumber): $($parseError.Message)")
                }
            }
            '.json' {
                try {
                    $null = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
                }
                catch {
                    $failures.Add("${file}: invalid JSON: $($_.Exception.Message)")
                }
            }
            '.md' {
                $text = Get-Content -LiteralPath $path -Raw
                foreach ($match in [regex]::Matches($text, '\]\((?<target>[^\s)]+)(?:\s+"[^"]*")?\)')) {
                    $target = $match.Groups['target'].Value.Trim('<', '>')
                    if ($target -match '^(?:[a-zA-Z][a-zA-Z0-9+.-]*:|#)' -or
                        $target -match '[<>]') {
                        continue
                    }
                    $target = [uri]::UnescapeDataString(($target -split '#', 2)[0])
                    if ($target) {
                        $resolved = Join-Path (Split-Path $path -Parent) $target
                        if (-not (Test-Path -LiteralPath $resolved)) {
                            $failures.Add("${file}: missing local link target: $target")
                        }
                    }
                }
            }
        }
    }

    if ($failures.Count -gt 0) {
        throw "Repository checks failed ($($failures.Count)):`n$($failures -join "`n")"
    }
    Write-Host "Repository checks passed for $($files.Count) files. No Azure operations were performed."
}
finally {
    Pop-Location
}
