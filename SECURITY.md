# Security

These examples are educational and intended for dev/test use with synthetic
data. They are not a production security baseline.

## Report a vulnerability privately

Do not disclose vulnerabilities, credentials, or exploit details in public
issues or pull requests.

Use GitHub's **Security > Advisories > Report a vulnerability** for this
repository:

[Report a vulnerability](https://github.com/rgward/sqlhyperscalebook/security/advisories/new)

This route requires private vulnerability reporting to be enabled by the
maintainer. If GitHub does not offer it, do not fall back to a public disclosure:
ask the maintainer to enable private reporting without including sensitive
details.

Include the affected chapter and file, impact, and minimal reproduction steps.
Use synthetic data and redact all environment-specific values.

For vulnerabilities in Microsoft products or services rather than these
examples, follow the [Microsoft Security Response Center reporting guidance](https://www.microsoft.com/msrc).

## Accidentally exposed credentials

Revoke or rotate an exposed credential immediately. Deleting a file or
redacting a later commit does not remove it from Git history, forks, or clones.
Coordinate any required history cleanup with the maintainer before publishing.
