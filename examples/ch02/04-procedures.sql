/* ============================================================================
   Inside Azure SQL Hyperscale — Chapter 2
   04-procedures.sql : foundational read/write procedures for the chart.
   Run order         : 4 of 5  (after 03-views.sql)

   Surface area kept intentionally small:
     * clinical.GetPatientChart       — read by encounter id
     * clinical.GetPatientChartByBed  — read the active encounter on a bed
     * clinical.AdmitPatient          — open an encounter and occupy a bed
     * clinical.DischargePatient      — close the encounter and free the bed
     * clinical.RecordVitals          — append an observation
     * clinical.PlaceMedicationOrder  — append a medication order
     * clinical.FileLabResult         — append a lab result (JSON payload)
     * clinical.AddClinicalNote       — append a free-text note

   The admit/discharge procedures are the only multi-statement transactions
   in the book's through-line: each touches two tables (Encounter + Bed)
   and the pair must be atomic to keep the bedside invariant
   "at most one active encounter per bed" honest. Single-statement DML is
   already atomic on its own and stays that way (no surplus BEGIN TRAN).
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

/* ---- Read: chart for a specific encounter ------------------------------ */
CREATE OR ALTER PROCEDURE clinical.GetPatientChart
    @EncounterId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT *
    FROM clinical.vPatientChart
    WHERE EncounterId = @EncounterId;
END;
GO

/* ---- Read: chart for whoever is currently in a bed --------------------- */
CREATE OR ALTER PROCEDURE clinical.GetPatientChartByBed
    @BedId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT vpc.*
    FROM clinical.vPatientChart AS vpc
    WHERE vpc.BedId = @BedId
      AND vpc.EncounterStatus = N'Active';
END;
GO

/* ---- Write: admit a patient (open encounter + occupy bed) -------------- */
CREATE OR ALTER PROCEDURE clinical.AdmitPatient
    @PatientId            INT,
    @DepartmentId         INT,
    @AttendingProviderId  INT,
    @BedId                INT,
    @EncounterType        NVARCHAR(20) = N'Inpatient',
    @IntakeJson           JSON         = NULL,
    @EncounterId          INT          OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        /* Bed must currently be Available — and free of any active encounter.
           The filtered unique index UX_Encounter_ActiveBed is the ultimate
           guard, but checking up front gives a clean error message. */
        IF NOT EXISTS (
            SELECT 1
            FROM ops.Bed
            WHERE BedId     = @BedId
              AND BedStatus = N'Available'
        )
        BEGIN
            THROW 50001, 'Bed is not Available.', 1;
        END;

        IF EXISTS (
            SELECT 1
            FROM clinical.Encounter
            WHERE BedId  = @BedId
              AND Status = N'Active'
        )
        BEGIN
            THROW 50002, 'Bed already has an active encounter.', 1;
        END;

        INSERT INTO clinical.Encounter
            (PatientId, DepartmentId, AttendingProviderId, BedId,
             EncounterType, AdmitTime, Status, IntakeJson)
        VALUES
            (@PatientId, @DepartmentId, @AttendingProviderId, @BedId,
             @EncounterType, SYSUTCDATETIME(), N'Active', @IntakeJson);

        SET @EncounterId = SCOPE_IDENTITY();

        UPDATE ops.Bed
        SET BedStatus = N'Occupied'
        WHERE BedId = @BedId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

/* ---- Write: discharge (close encounter + free bed) --------------------- */
CREATE OR ALTER PROCEDURE clinical.DischargePatient
    @EncounterId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @BedId INT;

        SELECT @BedId = BedId
        FROM clinical.Encounter
        WHERE EncounterId = @EncounterId
          AND Status      = N'Active';

        /* If no active encounter, nothing to discharge. */
        IF @@ROWCOUNT = 0
        BEGIN
            THROW 50010, 'No active encounter to discharge.', 1;
        END;

        UPDATE clinical.Encounter
        SET Status        = N'Discharged',
            DischargeTime = SYSUTCDATETIME(),
            BedId         = NULL          -- release the FK so the bed can be reused
        WHERE EncounterId = @EncounterId;

        IF @BedId IS NOT NULL
        BEGIN
            UPDATE ops.Bed
            SET BedStatus = N'Cleaning'   -- not Available until EVS turns it over
            WHERE BedId = @BedId;
        END;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

/* ---- Write: record a single vital -------------------------------------- */
/* Single-statement DML — atomic on its own; no explicit transaction.      */
CREATE OR ALTER PROCEDURE clinical.RecordVitals
    @EncounterId     INT,
    @ObservationType NVARCHAR(20),
    @ValueNumeric    DECIMAL(9, 3),
    @Unit            NVARCHAR(20) = NULL,
    @RecordedAt      DATETIME2(3) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO clinical.Observation
        (EncounterId, PatientId, RecordedAt, ObservationType, ValueNumeric, Unit)
    SELECT
        e.EncounterId,
        e.PatientId,
        COALESCE(@RecordedAt, SYSUTCDATETIME()),
        @ObservationType,
        @ValueNumeric,
        @Unit
    FROM clinical.Encounter AS e
    WHERE e.EncounterId = @EncounterId;

    IF @@ROWCOUNT = 0
    BEGIN
        THROW 50020, 'Unknown encounter.', 1;
    END;
END;
GO

/* ---- Write: place a medication order ----------------------------------- */
/* Single-statement DML — atomic on its own; no explicit transaction. */
CREATE OR ALTER PROCEDURE clinical.PlaceMedicationOrder
    @EncounterId    INT,
    @MedicationName NVARCHAR(200),
    @Dose           NVARCHAR(50)  = NULL,
    @Route          NVARCHAR(50)  = NULL,
    @OrderedById    INT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO clinical.MedicationOrder
        (EncounterId, PatientId, MedicationName, Dose, Route, OrderedById, OrderedAt)
    SELECT
        e.EncounterId,
        e.PatientId,
        @MedicationName,
        @Dose,
        @Route,
        @OrderedById,
        SYSUTCDATETIME()
    FROM clinical.Encounter AS e
    WHERE e.EncounterId = @EncounterId;

    IF @@ROWCOUNT = 0
    BEGIN
        THROW 50030, 'Unknown encounter.', 1;
    END;
END;
GO

/* ---- Write: file a lab result (semi-structured JSON payload) ------------ */
/* Single-statement DML — atomic on its own; no explicit transaction. The     */
/* JSON anchor that grows the LOB slice in Ch 10's grow-to-1tb demo.          */
CREATE OR ALTER PROCEDURE clinical.FileLabResult
    @EncounterId INT,
    @OrderedById INT,
    @TestName    NVARCHAR(100),
    @ResultJson  JSON,
    @CollectedAt DATETIME2(3) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO clinical.LabResult
        (EncounterId, PatientId, OrderedById, TestName, CollectedAt, ResultedAt,
         ResultJson, Status)
    SELECT
        e.EncounterId,
        e.PatientId,
        @OrderedById,
        @TestName,
        COALESCE(@CollectedAt, SYSUTCDATETIME()),
        SYSUTCDATETIME(),
        @ResultJson,
        N'Resulted'
    FROM clinical.Encounter AS e
    WHERE e.EncounterId = @EncounterId;

    IF @@ROWCOUNT = 0
    BEGIN
        THROW 50040, 'Unknown encounter.', 1;
    END;
END;
GO

/* ---- Write: add a free-text clinical note ------------------------------- */
/* Single-statement DML — atomic on its own; no explicit transaction. The     */
/* free-text anchor that grows the LOB slice in Ch 10's grow-to-1tb demo.     */
CREATE OR ALTER PROCEDURE clinical.AddClinicalNote
    @EncounterId      INT,
    @AuthorProviderId INT,
    @NoteType         NVARCHAR(20),
    @NoteText         NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO clinical.ClinicalNote
        (EncounterId, AuthorProviderId, NoteType, NoteText)
    SELECT
        e.EncounterId,
        @AuthorProviderId,
        @NoteType,
        @NoteText
    FROM clinical.Encounter AS e
    WHERE e.EncounterId = @EncounterId;

    IF @@ROWCOUNT = 0
    BEGIN
        THROW 50050, 'Unknown encounter.', 1;
    END;
END;
GO
