# Contributing

Thank you for helping readers run the examples from **Azure SQL Hyperscale
Unveiled**.

## Report an issue or erratum

Use [GitHub issues](https://github.com/rgward/sqlhyperscalebook/issues) for
reproducible example-code problems, documentation corrections, and book errata.
Include:

- The chapter and file, plus the book section or page when relevant.
- What you expected and what actually happened.
- Relevant PowerShell, Azure CLI, .NET SDK, or SQL client versions.
- Minimal reproduction steps and sanitized error output.

Never attach credentials, tokens, connection strings, local environment files,
or subscription-specific evidence. Report vulnerabilities privately as
described in [SECURITY.md](SECURITY.md).

## Propose a change

Keep pull requests focused on a single correction. Follow the owning chapter's
README and preserve the continuous Collier Health / Ward General scenario.
Use PowerShell 7 and Azure CLI for control-plane scripts, retain SQL SET-option
preambles, and use the existing stored procedures for application operations.
All example data must remain synthetic.

Update directly related documentation. Explain any changed prerequisites,
costs, approval gates, cleanup behavior, or re-run behavior.

When you change a Copilot skill under `.github/skills/`, keep its
`description` to 1,024 characters or fewer and keep the book's prompts in it.
Copilot reads only the description when choosing a skill, and it silently drops
a skill whose description is longer. Then run
`./tests/Measure-SkillRouting.ps1` to confirm the book's prompts still route to
the right skill.

## Validate locally

From the repository root, run the offline test suite in PowerShell 7. It needs
[Pester](https://pester.dev) 5.5 or later and the .NET 10 SDK:

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -Force -SkipPublisherCheck
./tests/Invoke-BookTests.ps1
```

The suite runs the static checks in `tools/validate-repository.ps1`. Those
checks parse PowerShell and JSON, check local Markdown link targets, and reject
local configuration, generated artifacts, and author-only review files.

The suite then checks the repository's conventions, the Copilot skills, and the
prompts and links printed in the book. It runs the preview, approval, and
safety paths of the billable and destructive scripts against a fake Azure CLI.
Finally, it fails if a new example isn't covered by the live tier. It doesn't
connect to Azure. See [tests/README.md](tests/README.md) for details, and for
how to add tests for a new or changed example.

For application or probe changes, use the .NET 10 SDK:

```powershell
dotnet build .\examples\ch04-first-app\WardGeneral.slnx --configuration Release
dotnet build .\examples\ch08-security\auditing\session-context-probe\SessionContextProbe.csproj --configuration Release
dotnet build .\examples\ch09-ha-resiliency\failover\retry-probe\RetryProbe.csproj --configuration Release
```

The repository-checks workflow runs these checks and the offline suite without
Azure credentials.
The application data library and auditing probe explicitly pin
`System.Security.Cryptography.Pkcs` to 9.0.21 to override vulnerable transitive
SQL client dependencies. Keep that dependency on a patched version when
updating packages; CI treats NuGet vulnerability warnings as errors.
For changes that need a database, run the affected chapters with the live tier
against a dev/test subscription:
`./tests/Invoke-BookTests.ps1 -Live -AcceptCharges -Chapter 2,3,4,5` runs
Chapters 2 through 5. Include every chapter from 2 up to the one you changed,
because each chapter builds on the ones before it. The run creates billable
resources and deletes them afterwards. Record what you tested. A successful
build or offline run is not a live Azure test.

Before publishing changes, install [Gitleaks](https://github.com/gitleaks/gitleaks)
and scan the working tree and all locally available Git history:

```powershell
gitleaks dir . --redact --no-banner
gitleaks git . --log-opts="--all" --redact --no-banner
```

Use a full clone with all intended public branches and tags for the history
scan. The configuration excludes only one exact synthetic request ID that
resembles a key. Do not add broad exclusions to hide findings. A clean scan
does not guarantee that all sensitive information has been found.
