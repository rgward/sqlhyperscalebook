# Chapter 8 — Securing Data in the Cloud with Hyperscale

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
