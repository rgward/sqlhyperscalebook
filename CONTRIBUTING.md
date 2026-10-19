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

## Validate locally

From the repository root, run the static checks in PowerShell 7:

```powershell
.\tools\validate-repository.ps1
```

These checks parse PowerShell and JSON, check local Markdown link targets, and
reject local configuration, generated artifacts, and author-only review files.
They do not execute chapter scripts, connect to Azure, or validate SQL behavior.

For application or probe changes, use the .NET 10 SDK:

```powershell
dotnet build .\examples\ch04-first-app\WardGeneral.slnx --configuration Release
dotnet build .\examples\ch08-security\auditing\session-context-probe\SessionContextProbe.csproj --configuration Release
dotnet build .\examples\ch09-ha-resiliency\failover\retry-probe\RetryProbe.csproj --configuration Release
```

The repository-checks workflow runs these checks without Azure credentials.
The application data library and auditing probe explicitly pin
`System.Security.Cryptography.Pkcs` to 9.0.21 to override vulnerable transitive
SQL client dependencies. Keep that dependency on a patched version when
updating packages; CI treats NuGet vulnerability warnings as errors.
For changes that need a database, follow the owning chapter's verification
steps against your own dev/test resources. Record what you tested and clean up
any billable resources afterward. A successful build is not a live Azure test.

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
