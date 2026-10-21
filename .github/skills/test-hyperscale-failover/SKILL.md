---
name: test-hyperscale-failover
description: >-
  Run the Chapter 9 Ward General failover and application-retry demonstration:
   preview and explicitly approve one manual Azure SQL database failover, start
   the finite .NET probe that references the app's existing
   Microsoft.Data.SqlClient retry provider, observe retry and recovery events,
   and report measured interruption without presenting it as an RTO. USE WHEN the
  reader says "run the Chapter 9 failover demo", "test Ward General failover",
  "show the retry logic during failover", "test application resiliency",
  "trigger a wardgeneral failover", or "observe retries during failover". Do
  not change HA replica count, zone redundancy, application code, or patient
  data.
---

# Test Hyperscale failover — Chapter 9

Read `examples/ch09-ha-resiliency/README.md` and
`examples/ch09-ha-resiliency/failover/README.md` before running anything. They
are the reader-facing source of truth and must remain capability-equivalent to
this skill.

## Scope and safety

This workflow runs an idempotent read probe and invokes the Azure SQL database
failover API once. The failover is intrusive and Azure permits only one call
per database every 15 minutes.

- Never run the failover without showing the preview and obtaining explicit
  approval.
- Never change the HA replica count or zone-redundancy configuration.
- Never modify or restart Ward General.
- Never edit or copy `RetryPolicy`; the probe references `WardGeneral.Data`.
- The probe must use the production connection provider and explicitly
   read-only command provider. Do not broaden retries to writes.
- SqlClient 7 requires the shared data project to reference
   `Microsoft.Data.SqlClient.Extensions.Azure` for `ActiveDirectoryDefault`.
   If the probe reports a missing authentication provider, stop it and do not
   submit the failover.
- Do not claim the measured interruption is a promised RTO.

## Workflow

1. Run `check-failover-health.ps1` with its default `Before` phase. Require
   `FailoverHealthPrecheck=PASS`. Report the exact resource, region, Resource
   Health state, summary, and timestamp. Preserve the JSON evidence path. Do
   not proceed if the script blocks the preflight.
2. Run `trigger-failover.ps1` without `-Execute`. Report the subscription,
   database resource ID, edition, zone-redundancy value, throttle, and exact
   REST request.
3. Obtain explicit approval for the exact database shown in the preview.
4. After approval, start `run-retry-probe.ps1` in a persistent terminal because
   it must remain visible while the failover runs. Require several `OK` rows
   before proceeding. Preserve the printed `ProbeEvidence` path; the launcher
   displays each line live and writes the same lines to `probe-output.txt`.
   The two-minute observation window starts after the first successful request;
   preserve `MeasurementEndsUtc` and do not submit the failover if too little
   time remains to observe recovery.
5. Immediately run `trigger-failover.ps1 -Execute` once. The approval applies
   only to the resource shown in the preview. Do not retry a rejected or
   throttled failover call automatically.
6. Observe the existing probe. Preserve every `DELAYED`, `RETRY`, `RECOVERED`,
   and `FAILED` row. A `DELAYED` row is a success that needed no retry but took
   at least 1,000 ms; the gateway can absorb a failover that way without the
   retry provider firing. A listed transient error can raise `RETRY`; an
   unlisted error fails that operation. Do not start a second probe.
7. Let the finite probe complete, or stop it only after successful requests
   have resumed and enough post-recovery rows exist to establish stability.
8. Preserve the first and final probe UTC timestamps. Run
   `collect-failover-evidence.ps1 -StartUtc <first> -EndUtc <final>` once. It
   saves the exact database's Activity Log, reuses Chapter 7's read-only SQL
   for a post-failover replica snapshot, and saves bounded Azure Monitor
   availability, connection, firewall, and replication-lag results.
9. If Activity Log or metric values have not arrived, preserve the same fixed
   interval and report **not yet delivered**. Do not poll, widen the interval,
   or generate another failover. The same collector can be rerun later with
   the original timestamps.
10. Run `check-failover-health.ps1 -Phase After`. Preserve the postcheck state,
   reported timestamp, and JSON evidence path. Resource Health is coarse
    supporting evidence, not the client interruption measurement.
11. Kill the persistent terminal after the probe exits.

## Required report

Report the exact database and resource ID, failover requested/accepted UTC,
last successful request before retry activity, retry errors and delays, first
recovered success, any delayed success, any exhausted operation, the probe
summary counts, and the normal-request latency median, average, and 95th
percentile with the maximum successful-request latency.
Include Resource Health before and after the failover.
Include Activity Log operation/status/correlation ID, post-failover replica
synchronization evidence, and all returned Azure Monitor values or explicit
not-yet-delivered limitations. Include the `probe-output.txt` path with the
other evidence files. Calculate observed interruption only from probe
timestamps. State that the run tests application transient-fault handling and
is not a contractual RTO.

## Files

| File | Role |
| --- | --- |
| `examples/ch09-ha-resiliency/failover/README.md` | Reader runbook and safety boundary |
| `examples/ch09-ha-resiliency/failover/check-failover-health.ps1` | Before/after Resource Health evidence for the exact database |
| `examples/ch09-ha-resiliency/failover/run-retry-probe.ps1` | Configuration loader and finite probe launcher |
| `examples/ch09-ha-resiliency/failover/trigger-failover.ps1` | Preview-first failover REST driver |
| `examples/ch09-ha-resiliency/failover/collect-failover-evidence.ps1` | Bounded Activity Log, replica, and Azure Monitor collector |
| `examples/ch09-ha-resiliency/failover/retry-probe/` | .NET probe referencing the application data project |
