# Chapter 8 — Securing Data in the Cloud with Hyperscale

> **Figures:** this chapter's book figures are in [`figures/ch08-security/`](../../figures/ch08-security/),
> listed with their captions in the [root README](../../README.md#chapter-8).

Chapter 8 has one primary guided example: secure the existing Ward General
application with Row-Level Security. It also has an optional Azure SQL Database
auditing companion investigation that captures a bounded interval of
application activity. Neither workflow creates a parallel application.

You must have deployed the Hyperscale database in Chapter 2. In addition, you
must have built and deployed the application from Chapters 4, 5, and 6. The
cumulative application, Chapter 5 AI objects, Chapter 6 SQL contracts, and
Chapter 6 DAB configuration are prerequisites. Chapter 8 does not redeploy
them; it changes their security boundary and rebuilds the app where necessary.

Start with the [`rls/` README](rls/) for the primary example or the
[`auditing/` README](auditing/) for the optional audit investigation. The
[`tde/` README](tde/) documents the separate optional Azure workflow that
configures a versionless customer-managed key as the logical server's TDE
protector. These workflows reuse the server and database configured in
[`../ch04-first-app/ch04.env`](../ch04-first-app/ch04.env.template).

Use the canonical VS Code Chat invocations in [`prompts.md`](prompts.md).

The setup command deploys the policy,
rebuilds the cumulative app, and validates a secured form of the existing DAB
configuration, then exits. As in Chapters 4–6, the reader starts DAB visibly in
one terminal and Ward General visibly in another terminal. No hidden console or
background runtime owns either process.

The chapter discusses Microsoft Entra-only authentication, database roles,
Private Link, data classification, ledger, and Defender for SQL without
packaging them as additional guided examples. The optional TDE workflow creates
a Key Vault and changes the server-level encryption protector immediately; it
is not preview-only. The optional auditing investigation provisions a billable
Log Analytics destination, captures application evidence, and has a guarded
teardown. The manuscript shows representative audit output and explains the
existing Chapter 5 ledger table conceptually. The application runs from a
laptop, so Private Link is architecture discussion rather than a live exercise.

**All data is synthetic. There is no real patient data (PHI) here.**

## Links from the book

Every web link printed in Chapter 8, in the order it appears, so you can click
instead of typing it. Cross-references to other chapters and links to this
repository are left out.

- Row-level security (RLS) — <https://aka.ms/sqlrls>
- Ledger — <https://aka.ms/sqlledger>
- User-assigned managed identity for Azure SQL — <https://learn.microsoft.com/azure/azure-sql/database/authentication-azure-ad-user-assigned-managed-identity>
- Outbound firewall rules — <https://learn.microsoft.com/azure/azure-sql/database/outbound-firewall-rule-overview>
- Transparent data encryption (TDE) — <https://aka.ms/sqltde>
- Always Encrypted with secure enclaves — <https://aka.ms/sqlae>
- Research paper on Always Encrypted and secure enclaves — <https://dl.acm.org/doi/epdf/10.1145/3318464.3386141>
- Azure SQL Database auditing — <https://aka.ms/azuresqlaudit>
- Microsoft Defender for SQL — <https://learn.microsoft.com/azure/defender-for-cloud/defender-for-sql-introduction>
