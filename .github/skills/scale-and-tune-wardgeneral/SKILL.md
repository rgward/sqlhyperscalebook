---
name: scale-and-tune-wardgeneral
description: 'Run the complete three-demo Chapter 10 Ward General performance progression in order. USE WHEN the reader says "run all Chapter 10 performance demos", "run the complete Chapter 10 progression", "walk me through every Chapter 10 demo", or "scale and tune Ward General end to end". Delegates each demo to its own skill: scale-wardgeneral-compute, grow-wardgeneral-database, and tune-wardgeneral-data. Do not use for a request naming only one demo.'
---

# Scale and tune Ward General

Drive the three-stage progression documented in
`examples/ch10-performance/README.md`. Treat the README as the reader-facing
source of truth. Each demo-specific skill owns its implementation details:

1. `scale-wardgeneral-compute`
2. `grow-wardgeneral-database`
3. `tune-wardgeneral-data`

## Routing

Run the three owning skills in order. Let each one control its prerequisites,
commands, measurements, implementation state, and stop conditions. Do not
duplicate those details here.

If a stage stops or remains design-only, report that state and do not advance
automatically.

Demo 3 currently runs the JSON-index and memory grant feedback sequences.
Observation tuning remains deferred; report that boundary rather than treating
it as a third runnable sequence.

## Shared guardrails

- Reuse the existing `wardgeneral` database and cumulative application.
- Load reader configuration from the chapter environment files; never discover
  or hard-code live resource names.
- Use passwordless Microsoft Entra authentication. Never request a database
  password.
- Preview every billable Azure change and obtain explicit approval.
- Consume Chapter 7 observability and Chapter 9 resiliency evidence without
  re-teaching those chapters.
