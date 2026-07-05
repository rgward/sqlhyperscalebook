/* ============================================================================
   Azure SQL Hyperscale Unveiled — Chapter 2
   02-tables.sql   : the Ward General through-line schema (tables only)
   Run order       : 2 of 5

   Notes for later chapters (NOT created here):
     * Ch 5  adds a VECTOR embedding column to clinical.ClinicalNote.
     * Ch 10 adds a JSON index on clinical.Encounter.IntakeJson as data grows
             (CREATE JSON INDEX requires a clustered key and is an offline build).
     * Ch 8  adds RLS predicates (ops.Provider.EntraObjectId,
             clinical.Encounter.AttendingProviderId) and dynamic data masking.
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

/* ---- Drop in reverse dependency order (idempotent re-run) ---------------- */
DROP TABLE IF EXISTS clinical.LabResult;
DROP TABLE IF EXISTS clinical.Allergy;
DROP TABLE IF EXISTS clinical.MedicationOrder;
DROP TABLE IF EXISTS clinical.Observation;
DROP TABLE IF EXISTS clinical.ClinicalNote;
DROP TABLE IF EXISTS clinical.Diagnosis;
DROP TABLE IF EXISTS ops.Appointment;
DROP TABLE IF EXISTS clinical.Encounter;
DROP TABLE IF EXISTS ops.Bed;
DROP TABLE IF EXISTS ops.Unit;
DROP TABLE IF EXISTS clinical.Patient;
DROP TABLE IF EXISTS ops.Provider;
DROP TABLE IF EXISTS ops.Department;
GO

/* ---- ops.Department ------------------------------------------------------ */
CREATE TABLE ops.Department
(
    DepartmentId  INT            NOT NULL IDENTITY(1, 1),
    Name          NVARCHAR(100)  NOT NULL,
    Specialty     NVARCHAR(100)  NULL,
    CONSTRAINT PK_Department PRIMARY KEY CLUSTERED (DepartmentId),
    CONSTRAINT UQ_Department_Name UNIQUE (Name)
);
GO

/* ---- ops.Unit ------------------------------------------------------------ */
/* Nursing unit / physical location (3 West, ICU). Second RLS axis (Ch 8).    */
CREATE TABLE ops.Unit
(
    UnitId        INT            NOT NULL IDENTITY(1, 1),
    Name          NVARCHAR(100)  NOT NULL,
    UnitType      NVARCHAR(30)   NOT NULL,   -- ICU | Med-Surg | ED | Telemetry | OR | L&D
    DepartmentId  INT            NULL,       -- a unit may align with a department
    CONSTRAINT PK_Unit PRIMARY KEY CLUSTERED (UnitId),
    CONSTRAINT UQ_Unit_Name UNIQUE (Name),
    CONSTRAINT FK_Unit_Department
        FOREIGN KEY (DepartmentId) REFERENCES ops.Department (DepartmentId)
);
GO

/* ---- ops.Bed ------------------------------------------------------------- */
/* A bed within a Unit; the bedside chart is opened by bed (Ch 4 app).        */
CREATE TABLE ops.Bed
(
    BedId         INT            NOT NULL IDENTITY(1, 1),
    UnitId        INT            NOT NULL,
    BedNumber     NVARCHAR(20)   NOT NULL,   -- e.g. '3W-12A'
    BedStatus     NVARCHAR(20)   NOT NULL CONSTRAINT DF_Bed_BedStatus DEFAULT N'Available',
                                             -- Available | Occupied | Cleaning | OutOfService
    CONSTRAINT PK_Bed PRIMARY KEY CLUSTERED (BedId),
    CONSTRAINT UQ_Bed_UnitNumber UNIQUE (UnitId, BedNumber),
    CONSTRAINT FK_Bed_Unit
        FOREIGN KEY (UnitId) REFERENCES ops.Unit (UnitId),
    CONSTRAINT CK_Bed_Status
        CHECK (BedStatus IN (N'Available', N'Occupied', N'Cleaning', N'OutOfService'))
);
GO

/* ---- ops.Provider -------------------------------------------------------- */
CREATE TABLE ops.Provider
(
    ProviderId    INT              NOT NULL IDENTITY(1, 1),
    FullName      NVARCHAR(200)    NOT NULL,
    DepartmentId  INT              NOT NULL,
    Role          NVARCHAR(50)     NOT NULL,
    EntraObjectId UNIQUEIDENTIFIER NULL,   -- maps to Microsoft Entra for RLS (Ch 8)
    CONSTRAINT PK_Provider PRIMARY KEY CLUSTERED (ProviderId),
    CONSTRAINT FK_Provider_Department
        FOREIGN KEY (DepartmentId) REFERENCES ops.Department (DepartmentId)
);
GO

/* ---- clinical.Patient ---------------------------------------------------- */
/* Email / Phone / MRN are the regex-validation targets in Ch 4 (REGEXP_LIKE). */
/* InsuranceJson is the native json showcase queried in Ch 5.                  */
CREATE TABLE clinical.Patient
(
    PatientId     INT            NOT NULL IDENTITY(1, 1),
    MRN           VARCHAR(12)    NOT NULL,        -- format WG-#######
    FullName      NVARCHAR(200)  NOT NULL,
    DateOfBirth   DATE           NOT NULL,
    Sex           NVARCHAR(20)   NOT NULL,
    Email         NVARCHAR(256)  NULL,
    Phone         VARCHAR(32)    NULL,
    City          NVARCHAR(100)  NULL,
    PostalCode    VARCHAR(12)    NULL,
    InsuranceJson JSON           NULL,            -- native JSON (GA on Azure SQL DB)
    CreatedAt     DATETIME2(3)   NOT NULL CONSTRAINT DF_Patient_CreatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Patient PRIMARY KEY CLUSTERED (PatientId),
    CONSTRAINT UQ_Patient_MRN UNIQUE (MRN)
);
GO

/* ---- clinical.Encounter -------------------------------------------------- */
/* The chart's spine. BedId is set while the patient is admitted; the filtered  */
/* unique index below enforces "a bed has ≤1 active encounter" (outline §3).  */
/* IntakeJson is the json column that earns a JSON index in Ch 10 at scale.    */
CREATE TABLE clinical.Encounter
(
    EncounterId         INT          NOT NULL IDENTITY(1, 1),
    PatientId           INT          NOT NULL,
    DepartmentId        INT          NOT NULL,
    AttendingProviderId INT          NOT NULL,
    BedId               INT          NULL,    -- nullable: outpatient / pre-bed-assignment
    EncounterType       NVARCHAR(20) NOT NULL,   -- ED | Inpatient | Outpatient
    AdmitTime           DATETIME2(3) NOT NULL,
    DischargeTime       DATETIME2(3) NULL,
    Status              NVARCHAR(20) NOT NULL,   -- Active | Discharged
    IntakeJson          JSON         NULL,
    CONSTRAINT PK_Encounter PRIMARY KEY CLUSTERED (EncounterId),
    CONSTRAINT FK_Encounter_Patient
        FOREIGN KEY (PatientId) REFERENCES clinical.Patient (PatientId),
    CONSTRAINT FK_Encounter_Department
        FOREIGN KEY (DepartmentId) REFERENCES ops.Department (DepartmentId),
    CONSTRAINT FK_Encounter_Provider
        FOREIGN KEY (AttendingProviderId) REFERENCES ops.Provider (ProviderId),
    CONSTRAINT FK_Encounter_Bed
        FOREIGN KEY (BedId) REFERENCES ops.Bed (BedId),
    CONSTRAINT CK_Encounter_Type
        CHECK (EncounterType IN (N'ED', N'Inpatient', N'Outpatient')),
    CONSTRAINT CK_Encounter_Status
        CHECK (Status IN (N'Active', N'Discharged')),
    CONSTRAINT CK_Encounter_Discharge
        CHECK (DischargeTime IS NULL OR DischargeTime >= AdmitTime)
);
GO

/* ---- ops.Appointment ----------------------------------------------------- */
CREATE TABLE ops.Appointment
(
    AppointmentId  INT          NOT NULL IDENTITY(1, 1),
    PatientId      INT          NOT NULL,
    ProviderId     INT          NOT NULL,
    DepartmentId   INT          NOT NULL,
    ScheduledStart DATETIME2(3) NOT NULL,
    ScheduledEnd   DATETIME2(3) NOT NULL,
    Status         NVARCHAR(20) NOT NULL,   -- Scheduled | Completed | Cancelled | NoShow
    CONSTRAINT PK_Appointment PRIMARY KEY CLUSTERED (AppointmentId),
    CONSTRAINT FK_Appointment_Patient
        FOREIGN KEY (PatientId) REFERENCES clinical.Patient (PatientId),
    CONSTRAINT FK_Appointment_Provider
        FOREIGN KEY (ProviderId) REFERENCES ops.Provider (ProviderId),
    CONSTRAINT FK_Appointment_Department
        FOREIGN KEY (DepartmentId) REFERENCES ops.Department (DepartmentId),
    CONSTRAINT CK_Appointment_Window CHECK (ScheduledEnd > ScheduledStart)
);
GO

/* ---- clinical.Diagnosis -------------------------------------------------- */
CREATE TABLE clinical.Diagnosis
(
    DiagnosisId   INT           NOT NULL IDENTITY(1, 1),
    EncounterId   INT           NOT NULL,
    IcdCode       VARCHAR(10)   NOT NULL,
    Description   NVARCHAR(300) NULL,
    DiagnosedById INT           NOT NULL,
    CONSTRAINT PK_Diagnosis PRIMARY KEY CLUSTERED (DiagnosisId),
    CONSTRAINT FK_Diagnosis_Encounter
        FOREIGN KEY (EncounterId) REFERENCES clinical.Encounter (EncounterId),
    CONSTRAINT FK_Diagnosis_Provider
        FOREIGN KEY (DiagnosedById) REFERENCES ops.Provider (ProviderId)
);
GO

/* ---- clinical.ClinicalNote ----------------------------------------------- */
/* NoteText is the free-text column embedded in Ch 5 and regex-mined in Ch 5/8. */
CREATE TABLE clinical.ClinicalNote
(
    NoteId           INT            NOT NULL IDENTITY(1, 1),
    EncounterId      INT            NOT NULL,
    AuthorProviderId INT            NOT NULL,
    NoteType         NVARCHAR(20)   NOT NULL,   -- Progress | Discharge | Consult
    NoteText         NVARCHAR(MAX)  NOT NULL,
    CreatedAt        DATETIME2(3)   NOT NULL CONSTRAINT DF_Note_CreatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_ClinicalNote PRIMARY KEY CLUSTERED (NoteId),
    CONSTRAINT FK_Note_Encounter
        FOREIGN KEY (EncounterId) REFERENCES clinical.Encounter (EncounterId),
    CONSTRAINT FK_Note_Provider
        FOREIGN KEY (AuthorProviderId) REFERENCES ops.Provider (ProviderId),
    CONSTRAINT CK_Note_Type
        CHECK (NoteType IN (N'Progress', N'Discharge', N'Consult'))
);
GO

/* ---- clinical.Observation  (the high-volume telemetry table) -------------- */
/* Modest seed in Ch 2; grown to large volume in Ch 10 for the page-server /   */
/* RBPEX / columnstore story. BIGINT key anticipates that growth.              */
CREATE TABLE clinical.Observation
(
    ObservationId   BIGINT        NOT NULL IDENTITY(1, 1),
    EncounterId     INT           NOT NULL,
    PatientId       INT           NOT NULL,
    RecordedAt      DATETIME2(3)  NOT NULL,
    ObservationType NVARCHAR(20)  NOT NULL,   -- HeartRate | BloodPressure | SpO2 | Temperature | RespRate
    ValueNumeric    DECIMAL(9, 3) NULL,
    Unit            NVARCHAR(20)  NULL,
    CONSTRAINT PK_Observation PRIMARY KEY CLUSTERED (ObservationId),
    CONSTRAINT FK_Observation_Encounter
        FOREIGN KEY (EncounterId) REFERENCES clinical.Encounter (EncounterId),
    CONSTRAINT FK_Observation_Patient
        FOREIGN KEY (PatientId) REFERENCES clinical.Patient (PatientId)
);
GO

/* ---- clinical.MedicationOrder -------------------------------------------- */
CREATE TABLE clinical.MedicationOrder
(
    OrderId        INT           NOT NULL IDENTITY(1, 1),
    EncounterId    INT           NOT NULL,
    PatientId      INT           NOT NULL,
    MedicationName NVARCHAR(200) NOT NULL,
    Dose           NVARCHAR(50)  NULL,
    Route          NVARCHAR(50)  NULL,
    OrderedById    INT           NOT NULL,
    OrderedAt      DATETIME2(3)  NOT NULL CONSTRAINT DF_Order_OrderedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_MedicationOrder PRIMARY KEY CLUSTERED (OrderId),
    CONSTRAINT FK_Order_Encounter
        FOREIGN KEY (EncounterId) REFERENCES clinical.Encounter (EncounterId),
    CONSTRAINT FK_Order_Patient
        FOREIGN KEY (PatientId) REFERENCES clinical.Patient (PatientId),
    CONSTRAINT FK_Order_Provider
        FOREIGN KEY (OrderedById) REFERENCES ops.Provider (ProviderId)
);
GO

/* ---- clinical.Allergy ---------------------------------------------------- */
/* High-value bedside recall surface for the Ch 6 clinical-assistant agent.    */
CREATE TABLE clinical.Allergy
(
    AllergyId   INT           NOT NULL IDENTITY(1, 1),
    PatientId   INT           NOT NULL,
    Substance   NVARCHAR(200) NOT NULL,        -- e.g. 'Penicillin', 'Latex'
    Reaction    NVARCHAR(200) NULL,            -- e.g. 'Hives', 'Anaphylaxis'
    Severity    NVARCHAR(20)  NOT NULL,        -- Mild | Moderate | Severe
    RecordedAt  DATETIME2(3)  NOT NULL CONSTRAINT DF_Allergy_RecordedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Allergy PRIMARY KEY CLUSTERED (AllergyId),
    CONSTRAINT FK_Allergy_Patient
        FOREIGN KEY (PatientId) REFERENCES clinical.Patient (PatientId),
    CONSTRAINT CK_Allergy_Severity
        CHECK (Severity IN (N'Mild', N'Moderate', N'Severe'))
);
GO

/* ---- clinical.LabResult -------------------------------------------------- */
/* ResultJson is the second native-json home (with Patient.InsuranceJson and  */
/* Encounter.IntakeJson). Lab result panels vary by test type, so the payload */
/* is naturally semi-structured.                                              */
CREATE TABLE clinical.LabResult
(
    LabResultId   BIGINT        NOT NULL IDENTITY(1, 1),
    EncounterId   INT           NOT NULL,
    PatientId     INT           NOT NULL,
    OrderedById   INT           NOT NULL,
    TestName      NVARCHAR(100) NOT NULL,       -- e.g. 'CBC', 'BMP', 'Troponin'
    CollectedAt   DATETIME2(3)  NOT NULL,
    ResultedAt    DATETIME2(3)  NULL,
    ResultJson    JSON          NULL,           -- panel values + reference ranges
    Status        NVARCHAR(20)  NOT NULL CONSTRAINT DF_Lab_Status DEFAULT N'Resulted',
                                                -- Ordered | Collected | Resulted | Cancelled
    CONSTRAINT PK_LabResult PRIMARY KEY CLUSTERED (LabResultId),
    CONSTRAINT FK_Lab_Encounter
        FOREIGN KEY (EncounterId) REFERENCES clinical.Encounter (EncounterId),
    CONSTRAINT FK_Lab_Patient
        FOREIGN KEY (PatientId) REFERENCES clinical.Patient (PatientId),
    CONSTRAINT FK_Lab_Provider
        FOREIGN KEY (OrderedById) REFERENCES ops.Provider (ProviderId),
    CONSTRAINT CK_Lab_Status
        CHECK (Status IN (N'Ordered', N'Collected', N'Resulted', N'Cancelled'))
);
GO

/* ---- Supporting nonclustered indexes (the joins every later chapter uses) - */
CREATE NONCLUSTERED INDEX IX_Encounter_PatientId
    ON clinical.Encounter (PatientId) INCLUDE (DepartmentId, AdmitTime, Status);
CREATE NONCLUSTERED INDEX IX_Encounter_BedId
    ON clinical.Encounter (BedId) INCLUDE (Status) WHERE BedId IS NOT NULL;
CREATE NONCLUSTERED INDEX IX_Observation_Encounter_RecordedAt
    ON clinical.Observation (EncounterId, RecordedAt);
CREATE NONCLUSTERED INDEX IX_Note_Encounter
    ON clinical.ClinicalNote (EncounterId);
CREATE NONCLUSTERED INDEX IX_Appointment_Provider_Start
    ON ops.Appointment (ProviderId, ScheduledStart);
CREATE NONCLUSTERED INDEX IX_Bed_UnitId
    ON ops.Bed (UnitId);
CREATE NONCLUSTERED INDEX IX_Allergy_PatientId
    ON clinical.Allergy (PatientId);
CREATE NONCLUSTERED INDEX IX_Lab_Encounter_CollectedAt
    ON clinical.LabResult (EncounterId, CollectedAt);
GO

/* ---- Bedside invariant: a bed has ≤1 active encounter --------------------- */
/* Filtered unique index. Filtered indexes require QUOTED_IDENTIFIER ON and    */
/* ANSI_NULLS ON (both set at the top of this file).                           */
CREATE UNIQUE NONCLUSTERED INDEX UX_Encounter_ActiveBed
    ON clinical.Encounter (BedId)
    WHERE BedId IS NOT NULL AND Status = N'Active';
GO
