---
name: grow-wardgeneral-database
description: 'Guide and run Chapter 10 Demo 2, driving the existing Ward General Hyperscale database with a five-minute 64-writer workload and identifying the actual write constraint from measured evidence. USE WHEN the reader says "Run Chapter 10 Demo 2: drive Ward General writes for five minutes and identify whether any constraints were observed in the measured evidence" (the book''s prompt), "run Chapter 10 Demo 2", "grow Ward General", "run the growth workload", "run another growth interval", "measure the Ward General write path", or "show automatic storage growth". Owns the numeric, JSON, and free-text growth path plus generated-log and resource evidence. Do not run compute Demo 1, change hardware families, tune indexes, or scale vector replicas.'
---

# Grow Ward General and find the constraint

Follow `examples/ch10-performance/02-grow-data/README.md`.
That README is the reader-facing source of truth.

## Boundaries

- Continue from Demo 1 at `HS_Gen5_40`.
- Reuse the same database and enlarge `clinical.Observation`,
  `clinical.LabResult`, and `clinical.ClinicalNote`.
- Run exactly one 300-second sqlsim interval per execution. Readers may repeat
  the same interval when they want more data.
- Keep the database at `HS_Gen5_40`; this demo does not change hardware.
- Do not claim log governance unless `RBIO_RG_*` and the measured log-rate
  evidence support it.

## Current workflow

1. Run `run-demo.ps1` without `-Execute` to show the exact database, current
  reserved size, SLO, workload duration, and sample interval.
2. Obtain explicit approval before rerunning the same command with `-Execute`;
  the operation appends billable data and has no automatic cleanup.
3. Let the runner launch the workload and capture 15-second samples from a
  separate connection. Do not ask the reader to manage a second terminal.
4. Read `summary.json`, `growth-timeline.csv`, and
  `performance-report.html` from the timestamped run directory.
5. Use the post-chart wait panel to report the `RBIO_RG_*` wait-type count,
  task count, total duration, dominant measured wait, and `WRITELOG` duration.
6. Interpret the actual constraint; do not infer a log-rate limit from growth
  volume alone. Leave the grown database ready for Demo 3.

Stop when approval is absent, the starting SLO is not `HS_Gen5_40`, the
workload fails, or live results contradict the planned narrative. Preserve a
partial run directory for diagnosis when a post-start failure occurs.
