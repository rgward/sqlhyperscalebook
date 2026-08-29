# Ward General database object catalog

This catalog covers the reader-deployed database objects through Chapter 6. Chapter 3 creates no objects; it inspects the Hyperscale architecture. Chapter 4 adds the application that uses the Chapter 2 contracts. Chapters 5 and 6 extend the database.

All patient data in the examples is synthetic.

## Schemas

| Object | Type | Chapter | Purpose | Used by | Notes |
| --- | --- | ---: | --- | --- | --- |
| `clinical` | Schema | 2 | Owns patient-linked clinical data. | All chart, AI, and agent contracts | Becomes the principal RLS surface in Chapter 8. |
| `ops` | Schema | 2 | Owns hospital organization, staffing, beds, and appointments. | Unit board, chart joins, seed, and write contracts | Separates operational reference data from clinical records. |

## Core tables

| Object | Type | Chapter | Purpose | Used by | Notes |
| --- | --- | ---: | --- | --- | --- |
| `ops.Department` | Table | 2 | Stores hospital departments and specialties. | Seed; unit, provider, encounter, and appointment foreign keys | Chapter 6 uses one department for the system-provider row. |
| `ops.Unit` | Table | 2 | Stores physical nursing units. | `ops.vBedCensus`; bed foreign key | A unit can align with a department. |
| `ops.Bed` | Table | 2 | Stores beds and their availability state. | `ops.vBedCensus`; encounter assignment; admit/discharge procedures | A bed is the Chapter 4 unit-board navigation key. |
| `ops.Provider` | Table | 2 | Stores clinicians and their future Entra mapping. | Chart joins and clinical write foreign keys | Chapter 6 adds `Ward General Assistant (system)` for honest unauthenticated attribution. |
| `ops.Appointment` | Table | 2 | Stores scheduled outpatient appointments. | Seed; later scale workloads | The Chapter 4–6 application does not read it yet. |
| `clinical.Patient` | Table | 2 | Stores patient identity, contact data, and insurance JSON. | Encounter and patient-scoped clinical tables | `InsuranceJson` uses the native `json` type. |
| `clinical.Encounter` | Table | 2 | Stores each admission and is the spine of the patient chart. | All encounter-scoped views and procedures | `IntakeJson` is the Chapter 10 JSON-index target. |
| `clinical.Diagnosis` | Table | 2 | Stores coded diagnoses for an encounter. | `clinical.vChartDiagnoses`; `clinical.GetHandoffCandidates` | It has no timestamp; Chapter 6 uses identity order only as a documented recency approximation. |
| `clinical.ClinicalNote` | Table | 2 | Stores free-text progress, consult, and discharge notes. | Chart views; Chapter 5 embedding and retrieval procedures | The vector is kept in a separate satellite table. |
| `clinical.Observation` | Table | 2 | Stores high-volume vital-sign observations. | Latest-vitals view; Chapter 6 trend evidence; Chapter 10 load | The nonclustered identity PK is separate from the clustered access path. |
| `clinical.MedicationOrder` | Table | 2 | Stores medication orders. | Chart view; Chapter 6 shift-window evidence | Written through `clinical.PlaceMedicationOrder`. |
| `clinical.Allergy` | Table | 2 | Stores patient-scoped allergies. | Chart view; Chapter 6 severe-allergy evidence | Patient-scoped so the record survives discharge. |
| `clinical.LabResult` | Table | 2 | Stores lab workflow state and semi-structured result JSON. | Recent-labs view; Chapter 6 pending-lab evidence | `ResultJson` uses the native `json` type. |
| `clinical.Symptom` | Table | 2 | Stores encounter presenting complaints. | `clinical.vChartSymptoms` | Read by the composite chart. |
| `clinical.CareTeamMember` | Table | 2 | Stores the providers assigned to an encounter. | `clinical.vChartCareTeam` | Enforces one membership row per encounter/provider pair. |
| `clinical.ImagingOrder` | Table | 2, 6 | Stores imaging orders and findings. | Chart view; seeded examples | Chapter 6 adds nullable `RequestKey`; the agent is deliberately not allowed to place orders. |

## Chart views

| Object | Type | Chapter | Purpose | Used by | Notes |
| --- | --- | ---: | --- | --- | --- |
| `clinical.vChartDiagnoses` | View | 2 | Projects encounter diagnoses as JSON. | `clinical.vPatientChart` | One row per encounter. |
| `clinical.vChartAllergies` | View | 2 | Projects patient allergies as JSON. | `clinical.vPatientChart` | Joined by patient, not encounter. |
| `clinical.vChartMedications` | View | 2 | Projects encounter medications as JSON. | `clinical.vPatientChart` | One row per encounter. |
| `clinical.vChartLatestVitals` | View | 2 | Selects the latest value of each vital type. | `clinical.vPatientChart` | Call through a filtered chart procedure; an unfiltered scan ranks the full observation table. |
| `clinical.vChartRecentLabs` | View | 2 | Projects the five most recent resulted labs. | `clinical.vPatientChart` | Ranks by result or collection time. |
| `clinical.vChartSymptoms` | View | 2 | Projects symptoms as JSON. | `clinical.vPatientChart` | One row per encounter. |
| `clinical.vChartCareTeam` | View | 2 | Projects care-team names and roles as JSON. | `clinical.vPatientChart` | Joins providers to encounter memberships. |
| `clinical.vChartImaging` | View | 2 | Projects the five most recent imaging orders. | `clinical.vPatientChart` | Includes the native-JSON findings document. |
| `clinical.vChartNotes` | View | 2 | Projects the five most recent clinical notes. | `clinical.vPatientChart` | This is current-chart text, not the historical vector-search corpus. |
| `clinical.vChartNoteSignals` | View | 2 | Extracts exact structured signals from the latest note with regular expressions. | `clinical.vPatientChart`; Chapter 4 chart | Demonstrates deterministic extraction from the same prose Chapter 5 embeds. |
| `clinical.vPatientChart` | View | 2 | Composes demographics and all chart sections into one encounter projection. | `clinical.GetPatientChart`; `clinical.GetPatientChartByBed`; AI assistance | The public procedures expose an explicit stable column list over it. |
| `ops.vBedCensus` | View | 2 | Shows bed occupancy and current patient/provider context. | Chapter 4 `ChartRepository` unit board | Read directly by the application. |

## Core stored procedures

| Object | Type | Chapter | Purpose | Used by | Notes |
| --- | --- | ---: | --- | --- | --- |
| `clinical.GetPatientChart` | Procedure | 2 | Returns the complete chart for one encounter. | Chapter 4 `ChartRepository`; Chapter 6 `get_patient_chart` MCP tool | Read-only stable contract over `clinical.vPatientChart`. |
| `clinical.GetPatientChartByBed` | Procedure | 2 | Returns the active chart for one bed. | Chapter 4 `ChartRepository`; Chapter 6 `get_patient_chart_by_bed` MCP tool | Read-only. |
| `clinical.SearchEncounters` | Procedure | 2 | Searches encounters with optional relational filters. | Chapter 4 `ChartRepository`; Chapter 6 `search_encounters` MCP tool | Its optional-predicate shape demonstrates OPPO. |
| `clinical.AdmitPatient` | Procedure | 2 | Atomically opens an encounter and occupies a bed. | Later workload harnesses; no Chapter 4 UI caller | One of two intentionally multi-statement transactions. |
| `clinical.DischargePatient` | Procedure | 2 | Atomically closes an encounter and moves its bed to cleaning. | Later workload harnesses; no Chapter 4 UI caller | Preserves the historical bed ID. |
| `clinical.RecordVitals` | Procedure | 2 | Appends one vital observation. | Later workload harnesses | One atomic `INSERT ... SELECT`; derives patient from encounter. |
| `clinical.PlaceMedicationOrder` | Procedure | 2 | Appends a medication order. | Later workload harnesses | No Chapter 4 UI caller. |
| `clinical.FileLabResult` | Procedure | 2 | Appends a resulted lab and its JSON payload. | Later workload harnesses | No Chapter 4 UI caller. |
| `clinical.AddClinicalNote` | Procedure | 2 | Appends a free-text clinical note. | Later workload harnesses | New notes become Chapter 5 embedding candidates. |
| `clinical.AddDiagnosis` | Procedure | 2 | Appends a coded diagnosis. | Later workload harnesses | No Chapter 4 UI caller. |
| `clinical.RecordAllergy` | Procedure | 2 | Appends a patient allergy. | Later workload harnesses | Validates a patient rather than an encounter. |

## AI objects

| Object | Type | Chapter | Purpose | Used by | Notes |
| --- | --- | ---: | --- | --- | --- |
| `[https://<your-foundry>.openai.azure.com/]` | Database-scoped credential | 5 | Lets the database managed identity call the Foundry model endpoint. | `WardGeneralEmbeddingModel`; direct assistance route | The deployed name is the reader's URL prefix; the secret value names a token audience, not an API key. |
| `[https://<your-apim>.azure-api.net/]` | Database-scoped credential | 5 | Lets the database managed identity call the APIM AI gateway. | `clinical.GenerateClinicalAssistance` | Created only after the placeholder is replaced. |
| `WardGeneralEmbeddingModel` | External model | 5 | Binds SQL embedding calls to `text-embedding-3-large`. | Embedding load; `clinical.GenerateClinicalAssistance`; `clinical.SearchSimilarNotes` | `MODEL_TYPE = EMBEDDINGS`; chat completions use the REST procedure instead. |
| `clinical.ClinicalNoteEmbeddings` | Table | 5 | Stores one 3,072-dimension `float16` vector per note. | Embedding load; vector index; AI procedures | One-to-one satellite keyed to `clinical.ClinicalNote`. |
| `clinical.AIAssistanceLog` | Append-only ledger table | 5 | Records every assistance request, response, parsed result, and timing. | `clinical.GenerateClinicalAssistance` | Tamper-evident and insert-only; the engine also creates ledger metadata objects. |
| `clinical.GenerateClinicalAssistance` | Procedure | 5 | Produces advisory triage and a grounded summary. | Chapter 4 `ChartRepository`; Chapter 6 `clinical_assistance` MCP tool | Retrieves similar notes, calls the chat deployment, and writes the ledger. |
| `clinical.SearchSimilarNotes` | Procedure | 5 | Performs filtered semantic retrieval over historical notes. | Chapter 4 `ResearchRepository`; Chapter 6 `search_clinical_context` MCP tool | Intended to run on the named research replica; retrieval only. |
| `research_reader` | Database role | 5 | Grants only the note, embedding, model, and search access needed by researchers. | Reader-created research users | No patient administration or write permissions. |

## Agent objects

| Object | Type | Chapter | Purpose | Used by | Notes |
| --- | --- | ---: | --- | --- | --- |
| `clinical.AgentRecommendation` | Table | 6 | Stores structured SBAR handoff proposals and their workflow state. | `clinical.SaveShiftHandoff` | Mutable workflow state, intentionally not a ledger table. |
| `clinical.GetHandoffCandidates` | Procedure | 6 | Gathers shift-window evidence for active patients. | Chapter 6 `get_handoff_candidates` MCP tool | Returns evidence, not a ranking; the model weighs it. |
| `clinical.SaveShiftHandoff` | Procedure | 6 | Saves one approval-gated SBAR handoff. | Chapter 6 `save_handoff` MCP tool | Derives patient and system-provider identity; request-key uniqueness makes retries idempotent. |
| `clinical.PlaceImagingOrder` | Procedure | 6 | Provides a bounded, idempotent imaging-order write contract. | None yet | Deliberately absent from DAB, MCP, and the application to demonstrate that database capability is not agent permission. |
| `Ward General Assistant (system)` | Seeded provider row | 6 | Attributes unauthenticated Chapter 6 handoffs truthfully. | `clinical.SaveShiftHandoff` | Chapter 8 replaces system attribution with authenticated clinician identity. |

## Indexes with a teaching role

Routine primary-key, foreign-key support, and chart-join indexes are defined in the table scripts but omitted here. These indexes carry an explicit chapter design point.

| Object | Type | Chapter | Purpose | Used by | Notes |
| --- | --- | ---: | --- | --- | --- |
| `CIX_Observation_Encounter_RecordedAt` | Unique clustered index | 2 | Distributes concurrent vital inserts by encounter while serving latest-vitals reads. | Observation writes and chart reads | Keeps `ObservationId` as the separate nonclustered primary key. |
| `UX_Encounter_ActiveBed` | Filtered unique index | 2 | Enforces at most one active encounter per bed. | `clinical.AdmitPatient` | The constraint, not the preliminary check, closes the concurrency race. |
| `VIX_ClinicalNoteEmbeddings_Embedding` | DiskANN vector index | 5 | Accelerates cosine nearest-neighbor search over note embeddings. | Both Chapter 5 AI procedures | Current generation supports DML and filtered approximate search. |
| `UQ_AgentRec_RequestKey` | Unique nonclustered index | 6 | Prevents duplicate handoffs under retry or concurrency. | `clinical.SaveShiftHandoff` | Plain uniqueness because every recommendation row requires a key. |
| `IX_AgentRec_Encounter` | Nonclustered index | 6 | Supports encounter-ordered handoff history. | Later workflow and audit reads | Keys on encounter and descending proposal time. |
| `UQ_Imaging_RequestKey` | Filtered unique index | 6 | Prevents duplicate keyed imaging orders without backfilling Chapter 2 rows. | `clinical.PlaceImagingOrder` | Filters out the existing rows whose request key is `NULL`. |

## Chapter 6 MCP mapping

DAB exposes only these seven named stored-procedure contracts. `runtime.mcp.dml-tools` is `false`, so generic CRUD and procedure-execution tools are not published.

| MCP tool | Database contract | Behavior |
| --- | --- | --- |
| `get_patient_chart` | `clinical.GetPatientChart` | Read current chart by encounter. |
| `get_patient_chart_by_bed` | `clinical.GetPatientChartByBed` | Read current chart by bed. |
| `search_encounters` | `clinical.SearchEncounters` | Read encounter summaries. |
| `search_clinical_context` | `clinical.SearchSimilarNotes` | Retrieve similar historical notes. |
| `get_handoff_candidates` | `clinical.GetHandoffCandidates` | Read shift-change evidence. |
| `clinical_assistance` | `clinical.GenerateClinicalAssistance` | Generate advisory assistance and append its audit record. |
| `save_handoff` | `clinical.SaveShiftHandoff` | Write a proposed handoff only after application approval. |
