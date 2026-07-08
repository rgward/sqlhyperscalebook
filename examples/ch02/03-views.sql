/* ============================================================================
   Azure SQL Hyperscale Unveiled — Chapter 2
   03-views.sql    : the digital patient chart, as a computed projection.
   Run order       : 3 of 5  (after 02-tables.sql)

   The chart is the bedside view of an admitted patient. It is NOT a stored
   blob — the normalized tables stay the source of truth. Each section
   (diagnoses, allergies, medications, latest vitals, recent labs) is its
   own helper view returning a `json` column built with JSON_OBJECTAGG /
   JSON_ARRAYAGG (GA May 2025); the composite `vPatientChart` joins them
   together by encounter.

   Conventions:
     * JSON columns in the views return the native `json` type (GA on Azure
       SQL Database). They are safe to pass through APIs unchanged.
     * Each view is CREATE OR ALTER so the file is re-runnable.
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

/* ---- Diagnoses --------------------------------------------------------- */
CREATE OR ALTER VIEW clinical.vChartDiagnoses
AS
SELECT
    d.EncounterId,
    JSON_ARRAYAGG(
        JSON_OBJECT(
            'code'        : d.IcdCode,
            'description' : d.Description,
            'byProviderId': d.DiagnosedById
        )
    ) AS Diagnoses
FROM clinical.Diagnosis AS d
GROUP BY d.EncounterId;
GO

/* ---- Allergies (per patient — survives discharge) ---------------------- */
CREATE OR ALTER VIEW clinical.vChartAllergies
AS
SELECT
    a.PatientId,
    JSON_ARRAYAGG(
        JSON_OBJECT(
            'substance' : a.Substance,
            'reaction'  : a.Reaction,
            'severity'  : a.Severity,
            'recordedAt': a.RecordedAt
        )
    ) AS Allergies
FROM clinical.Allergy AS a
GROUP BY a.PatientId;
GO

/* ---- Medication orders (the MAR section) ------------------------------- */
CREATE OR ALTER VIEW clinical.vChartMedications
AS
SELECT
    m.EncounterId,
    JSON_ARRAYAGG(
        JSON_OBJECT(
            'medication'   : m.MedicationName,
            'dose'         : m.Dose,
            'route'        : m.Route,
            'orderedById'  : m.OrderedById,
            'orderedAt'    : m.OrderedAt
        )
    ) AS Medications
FROM clinical.MedicationOrder AS m
GROUP BY m.EncounterId;
GO

/* ---- Latest vitals (most recent of each type per encounter) ------------ */
/* Ranks all Observation rows; only efficient when the caller filters by      */
/* encounter (the 04-procedures always do). Do not SELECT * FROM              */
/* vPatientChart unfiltered at scale — it would rank the whole table.         */
CREATE OR ALTER VIEW clinical.vChartLatestVitals
AS
WITH ranked AS
(
    SELECT
        o.EncounterId,
        o.ObservationType,
        o.ValueNumeric,
        o.Unit,
        o.RecordedAt,
        ROW_NUMBER() OVER (
            PARTITION BY o.EncounterId, o.ObservationType
            ORDER BY o.RecordedAt DESC
        ) AS rn
    FROM clinical.Observation AS o
)
SELECT
    r.EncounterId,
    JSON_OBJECTAGG(
        r.ObservationType :
            JSON_OBJECT(
                'value' : r.ValueNumeric,
                'unit'  : r.Unit,
                'at'    : r.RecordedAt
            )
    ) AS LatestVitals
FROM ranked AS r
WHERE r.rn = 1
GROUP BY r.EncounterId;
GO

/* ---- Recent resulted labs (last 5 per encounter) ----------------------- */
/* Ranks all resulted LabResult rows; filter by encounter (the procedures do). */
CREATE OR ALTER VIEW clinical.vChartRecentLabs
AS
WITH ranked AS
(
    SELECT
        l.EncounterId,
        l.TestName,
        l.CollectedAt,
        l.ResultedAt,
        l.ResultJson,
        ROW_NUMBER() OVER (
            PARTITION BY l.EncounterId
            ORDER BY COALESCE(l.ResultedAt, l.CollectedAt) DESC
        ) AS rn
    FROM clinical.LabResult AS l
    WHERE l.Status = N'Resulted'
)
SELECT
    r.EncounterId,
    JSON_ARRAYAGG(
        JSON_OBJECT(
            'test'        : r.TestName,
            'collectedAt' : r.CollectedAt,
            'resultedAt'  : r.ResultedAt,
            'result'      : r.ResultJson
        )
    ) AS RecentLabs
FROM ranked AS r
WHERE r.rn <= 5
GROUP BY r.EncounterId;
GO

/* ---- The patient chart ------------------------------------------------- */
/* Row per encounter. Joins the normalized facts to the per-section JSON   */
/* projections. Use procedures in 04-procedures.sql to fetch by encounter  */
/* or by bed; this view is the building block.                             */
CREATE OR ALTER VIEW clinical.vPatientChart
AS
SELECT
    /* Encounter spine */
    e.EncounterId,
    e.Status                                   AS EncounterStatus,
    e.EncounterType,
    e.AdmitTime,
    e.DischargeTime,
    e.IntakeJson,

    /* Patient */
    p.PatientId,
    p.MRN,
    p.FullName                                 AS PatientName,
    p.DateOfBirth,
    p.Sex,
    DATEDIFF(YEAR, p.DateOfBirth, SYSUTCDATETIME())
        - IIF((MONTH(p.DateOfBirth) > MONTH(SYSUTCDATETIME()))
           OR (MONTH(p.DateOfBirth) = MONTH(SYSUTCDATETIME())
               AND DAY(p.DateOfBirth) > DAY(SYSUTCDATETIME())), 1, 0) AS AgeYears,

    /* Location */
    d.DepartmentId,
    d.Name                                     AS DepartmentName,
    u.UnitId,
    u.Name                                     AS UnitName,
    b.BedId,
    b.BedNumber,

    /* Attending */
    pr.ProviderId                              AS AttendingProviderId,
    pr.FullName                                AS AttendingProviderName,
    pr.Role                                    AS AttendingProviderRole,

    /* Composite sections (json) */
    diag.Diagnoses,
    meds.Medications,
    allergy.Allergies,
    vit.LatestVitals,
    lab.RecentLabs
FROM clinical.Encounter             AS e
JOIN clinical.Patient               AS p   ON p.PatientId    = e.PatientId
JOIN ops.Department                 AS d   ON d.DepartmentId = e.DepartmentId
JOIN ops.Provider                   AS pr  ON pr.ProviderId  = e.AttendingProviderId
LEFT JOIN ops.Bed                   AS b   ON b.BedId        = e.BedId
LEFT JOIN ops.Unit                  AS u   ON u.UnitId       = b.UnitId
LEFT JOIN clinical.vChartDiagnoses    AS diag    ON diag.EncounterId    = e.EncounterId
LEFT JOIN clinical.vChartMedications  AS meds    ON meds.EncounterId    = e.EncounterId
LEFT JOIN clinical.vChartAllergies    AS allergy ON allergy.PatientId   = p.PatientId
LEFT JOIN clinical.vChartLatestVitals AS vit     ON vit.EncounterId     = e.EncounterId
LEFT JOIN clinical.vChartRecentLabs   AS lab     ON lab.EncounterId     = e.EncounterId;
GO

/* ---- Convenience: who is currently in which bed ------------------------ */
CREATE OR ALTER VIEW ops.vBedCensus
AS
SELECT
    u.Name              AS UnitName,
    b.BedNumber,
    b.BedStatus,
    e.EncounterId,
    p.PatientId,
    p.MRN,
    p.FullName          AS PatientName,
    pr.FullName         AS AttendingProvider,
    e.AdmitTime
FROM ops.Bed               AS b
JOIN ops.Unit              AS u  ON u.UnitId = b.UnitId
LEFT JOIN clinical.Encounter AS e ON e.BedId = b.BedId AND e.Status = N'Active'
LEFT JOIN clinical.Patient   AS p ON p.PatientId = e.PatientId
LEFT JOIN ops.Provider       AS pr ON pr.ProviderId = e.AttendingProviderId;
GO
