/* ============================================================================
   Azure SQL Hyperscale Unveiled — Chapter 2
   05-seed.sql      : reproducible synthetic seed for Ward General Hospital.
   Run order        : 5 of 5  (after 04-procedures.sql)

   What this script populates (volumes per the Ch 2 outline §3):

       ops.Department      ~ 12   (explicit)
       ops.Unit            ~ 20   (explicit)
       ops.Bed             ~400   (explicit)
       ops.Provider        ~150   (34 named + generated)
       clinical.Patient    ~ 10,000          (30 named + generated)
       clinical.Allergy    ~ 15,000
       clinical.Encounter  ~ 40,000          (400 active, rest discharged)
       ops.Appointment     ~120,000
       clinical.Diagnosis  ~ 80,000
       clinical.ClinicalNote ~ 50,000        (~1-2 KB per NoteText)
       clinical.MedicationOrder ~100,000
       clinical.LabResult  ~200,000          (~0.5-1 KB per ResultJson)
       clinical.Observation ~108M            (the size anchor; ~10 GB w/ indexes)

   Anchor target: a database a little over 10 GB after this seed completes.
   Ch 10 grows clinical.Observation to ~1 TB via a one-time author-run grow
   script — readers stay at the volumes seeded here.

   This is the through-line dataset. **All data is fully synthetic. No real
   PHI.** Recognisable names are *Seinfeld supporting cast* — used as flavour
   to make the data memorable. Jerry does not appear in this dataset.

   Knob (@Scale): the bulky tables Encounter (discharged), Appointment, and
   Observation each declare a local `@Scale FLOAT = 1.0` at the top of their
   batch. To scale the seed up or down, edit those three values together.
   Default 1.0 produces the volumes documented above. Reference data
   (Department / Unit / Bed / named Providers / named Patients) is not
   scaled by @Scale — those are deterministic constants.

   Run time: at @Scale = 1.0 expect ~5–15 minutes on a 4 vCore HS_Gen5
   primary (log-rate gated; see Ch 10 §5 for why).

   Idempotence: re-runnable. The script TRUNCATEs the synthesised tables
   and reseeds Patient / Provider / Department / Unit / Bed. Identity
   counters are reset.
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
SET XACT_ABORT ON;
SET NOCOUNT ON;
GO

/* ---------- Knobs --------------------------------------------------------
   Default volumes target ~10 GB after this script completes.
   Variables declared per-batch (the bulky tables Encounter / Appointment /
   Observation scale with @Scale); reference data does not scale.
   To scale the whole seed up or down, edit @Scale in each of the three
   batches below that declare it (search for `@Scale FLOAT`).
----------------------------------------------------------------------- */
GO

/* ============================================================================
   Reset (idempotent re-run)
   ============================================================================ */
PRINT N'--- Resetting tables ---';
TRUNCATE TABLE clinical.Observation;
TRUNCATE TABLE clinical.LabResult;
TRUNCATE TABLE clinical.MedicationOrder;
TRUNCATE TABLE clinical.ClinicalNote;
TRUNCATE TABLE clinical.Diagnosis;
TRUNCATE TABLE clinical.Allergy;
DELETE FROM ops.Appointment;            DBCC CHECKIDENT ('ops.Appointment',      RESEED, 0) WITH NO_INFOMSGS;
DELETE FROM clinical.Encounter;         DBCC CHECKIDENT ('clinical.Encounter',   RESEED, 0) WITH NO_INFOMSGS;
DELETE FROM clinical.Patient;           DBCC CHECKIDENT ('clinical.Patient',     RESEED, 0) WITH NO_INFOMSGS;
DELETE FROM ops.Provider;               DBCC CHECKIDENT ('ops.Provider',         RESEED, 0) WITH NO_INFOMSGS;
DELETE FROM ops.Bed;                    DBCC CHECKIDENT ('ops.Bed',              RESEED, 0) WITH NO_INFOMSGS;
DELETE FROM ops.Unit;                   DBCC CHECKIDENT ('ops.Unit',             RESEED, 0) WITH NO_INFOMSGS;
DELETE FROM ops.Department;             DBCC CHECKIDENT ('ops.Department',       RESEED, 0) WITH NO_INFOMSGS;
GO

/* ============================================================================
   1.  ops.Department  (12 rows, explicit)
   ============================================================================ */
PRINT N'--- ops.Department ---';
INSERT INTO ops.Department (Name, Specialty) VALUES
    (N'Cardiology',           N'Cardiology'),
    (N'Oncology',              N'Hematology-Oncology'),
    (N'Emergency Medicine',    N'Emergency Medicine'),
    (N'Internal Medicine',     N'Internal Medicine'),
    (N'Surgery',               N'General Surgery'),
    (N'Pediatrics',            N'Pediatrics'),
    (N'Obstetrics-Gynecology', N'OB-GYN'),
    (N'Orthopedics',           N'Orthopedic Surgery'),
    (N'Neurology',             N'Neurology'),
    (N'Pulmonology',           N'Pulmonary Medicine'),
    (N'Psychiatry',            N'Psychiatry'),
    (N'Radiology',             N'Radiology');
GO

/* ============================================================================
   2.  ops.Unit  (20 rows, explicit)
   ============================================================================ */
PRINT N'--- ops.Unit ---';
INSERT INTO ops.Unit (Name, UnitType, DepartmentId)
SELECT u.Name, u.UnitType, d.DepartmentId
FROM (VALUES
    (N'ED Main',          N'ED',         N'Emergency Medicine'),
    (N'ED Fast Track',    N'ED',         N'Emergency Medicine'),
    (N'ICU A',            N'ICU',        N'Internal Medicine'),
    (N'ICU B',            N'ICU',        N'Internal Medicine'),
    (N'3 West',           N'Med-Surg',   N'Internal Medicine'),
    (N'3 East',           N'Med-Surg',   N'Internal Medicine'),
    (N'4 North',          N'Telemetry',  N'Cardiology'),
    (N'4 South',          N'Telemetry',  N'Cardiology'),
    (N'5 West',           N'Med-Surg',   N'Oncology'),
    (N'5 East',           N'Telemetry',  N'Cardiology'),
    (N'L and D',          N'L&D',        N'Obstetrics-Gynecology'),
    (N'Postpartum',       N'Med-Surg',   N'Obstetrics-Gynecology'),
    (N'NICU',             N'ICU',        N'Pediatrics'),
    (N'PICU',             N'ICU',        N'Pediatrics'),
    (N'OR Suite A',       N'OR',         N'Surgery'),
    (N'OR Suite B',       N'OR',         N'Surgery'),
    (N'PACU',             N'Med-Surg',   N'Surgery'),
    (N'Same-Day Surgery', N'Med-Surg',   N'Surgery'),
    (N'Adult Psych',      N'Med-Surg',   N'Psychiatry'),
    (N'Geriatric Psych',  N'Med-Surg',   N'Psychiatry')
) u(Name, UnitType, DeptName)
JOIN ops.Department d ON d.Name = u.DeptName;
GO

/* ============================================================================
   3.  ops.Bed  (~400 rows; 20 beds per unit)
   ============================================================================ */
PRINT N'--- ops.Bed ---';
INSERT INTO ops.Bed (UnitId, BedNumber, BedStatus)
SELECT
    u.UnitId,
    CONCAT(LEFT(REPLACE(u.Name, N' ', N''), 4), N'-',
           RIGHT(CONCAT(N'00', gs.value), 3))               AS BedNumber,
    N'Available'                                            AS BedStatus
FROM ops.Unit u
CROSS JOIN GENERATE_SERIES(1, 20) gs;
GO

/* ============================================================================
   4.  ops.Provider  (34 named Seinfeld cast + Ward family + ~116 generated = 150)
   ============================================================================ */
PRINT N'--- ops.Provider (named: Seinfeld cast + Ward family, Jerry excluded) ---';
INSERT INTO ops.Provider (FullName, DepartmentId, Role, EntraObjectId)
SELECT v.FullName, d.DepartmentId, v.Role, NEWID()
FROM (VALUES
    /* The recurring four — minus Jerry */
    (N'Dr. Cosmo Kramer',          N'Internal Medicine',     N'Resident'),
    (N'Dr. Elaine Benes',          N'Cardiology',            N'Attending'),
    (N'Dr. George Costanza',       N'Psychiatry',            N'Resident'),
    /* Costanzas + Seinfeld parents + Uncle Leo */
    (N'Dr. Frank Costanza',        N'Cardiology',            N'Attending'),
    (N'Dr. Estelle Costanza',      N'Internal Medicine',     N'Attending'),
    (N'Dr. Helen Seinfeld',        N'Internal Medicine',     N'Attending'),
    (N'Dr. Morty Seinfeld',        N'Internal Medicine',     N'Attending'),
    (N'Dr. Leo Gerard',            N'Internal Medicine',     N'Hospitalist'),
    /* Canonical "Dr." in the show */
    (N'Dr. Tim Whatley',           N'Pulmonology',           N'Attending'),
    /* Recurring supporting cast */
    (N'Dr. Susan Ross',            N'Surgery',               N'Attending'),
    (N'Dr. David Puddy',           N'Orthopedics',           N'Attending'),
    (N'Dr. Jackie Chiles',         N'Emergency Medicine',    N'Attending'),
    (N'Dr. Jacopo Peterman',       N'Oncology',              N'Attending'),
    (N'Dr. Justin Pitt',           N'Internal Medicine',     N'Attending'),
    (N'Dr. Mickey Abbott',         N'Pediatrics',            N'Attending'),
    (N'Dr. Sidra Holland',         N'Obstetrics-Gynecology', N'Attending'),
    (N'Dr. Sue Ellen Mischke',     N'Obstetrics-Gynecology', N'Attending'),
    (N'Dr. Lloyd Braun',           N'Psychiatry',            N'Attending'),
    (N'Dr. Kenny Bania',           N'Internal Medicine',     N'Resident'),
    (N'Dr. Donna Chang',           N'Internal Medicine',     N'Resident'),
    (N'Dr. Bob Cobb',              N'Neurology',             N'Attending'),     -- the Maestro
    (N'Dr. Norman Lippman',        N'Psychiatry',            N'Attending'),
    (N'Dr. Carl Wilhelm',          N'Radiology',             N'Attending'),
    (N'Dr. Reggie Singer',         N'Emergency Medicine',    N'Resident'),
    (N'Dr. Tor Eckman',            N'Internal Medicine',     N'Resident'),     -- "holistic healer"
    (N'Dr. Babs Kramer',           N'Internal Medicine',     N'Hospitalist'),  -- Kramer's mother
    (N'Dr. Sally Weaver',          N'Pediatrics',            N'Resident'),
    (N'Dr. Russell Dalrymple',     N'Surgery',               N'Attending'),
    /* The Ward family — namesakes of Ward General Hospital */
    (N'Dr. Claudia Ward',          N'Internal Medicine',     N'Chief of Staff'),
    (N'Dr. Ginger Ward',           N'Cardiology',            N'Attending'),
    (N'Dr. Ryan Ward',             N'Surgery',               N'Resident'),
    (N'Dr. Troy Ward',             N'Emergency Medicine',    N'Attending'),
    (N'Dr. Blair Ward',            N'Pediatrics',            N'Attending'),
    (N'Dr. Elizabeth Ward',        N'Oncology',              N'Attending')
) v(FullName, DeptName, Role)
JOIN ops.Department d ON d.Name = v.DeptName;
GO

/* Generated providers — fill out to ~150 across all departments. */
INSERT INTO ops.Provider (FullName, DepartmentId, Role, EntraObjectId)
SELECT
    CONCAT(N'Dr. ',
        CHOOSE(((gs.value * 7) % 20) + 1,
               N'Alex',N'Sam',N'Jordan',N'Taylor',N'Morgan',N'Casey',
               N'Riley',N'Jamie',N'Dakota',N'Avery',N'Rowan',N'Quinn',
               N'Logan',N'Hayden',N'Drew',N'Emerson',N'Skyler',N'Reese',
               N'Phoenix',N'Sage'),
        N' ',
        CHOOSE(((gs.value * 13) % 20) + 1,
               N'Adler',N'Brooks',N'Carter',N'Donovan',N'Ellis',N'Foster',
               N'Garner',N'Hayes',N'Iverson',N'Jensen',N'Klein',N'Larson',
               N'Mercer',N'Novak',N'Owens',N'Park',N'Quinn',N'Reyes',
               N'Sanders',N'Tucker')),
    d.DepartmentId,
    CHOOSE(((gs.value * 11) % 4) + 1, N'Attending', N'Resident', N'Hospitalist', N'Fellow'),
    NEWID()
FROM GENERATE_SERIES(1, 116) gs
CROSS APPLY (
    SELECT TOP 1 DepartmentId
    FROM ops.Department
    ORDER BY (gs.value + DepartmentId) % 12
) d;
GO

/* ============================================================================
   5.  clinical.Patient  (30 named Seinfeld supporting cast + ~9,970 generated)
   ============================================================================ */
PRINT N'--- clinical.Patient (named: Seinfeld supporting cast) ---';

/* The named patients first — recognisable supporting cast, no Jerry. */
INSERT INTO clinical.Patient
    (MRN, FullName, DateOfBirth, Sex, Email, Phone, City, PostalCode, InsuranceJson)
SELECT
    CONCAT(N'WG-', RIGHT(CONCAT(N'000000', ROW_NUMBER() OVER (ORDER BY v.FullName)), 7)),
    v.FullName,
    v.DateOfBirth,
    v.Sex,
    v.Email,
    v.Phone,
    v.City,
    v.PostalCode,
    JSON_OBJECT(
        'insurer'           : v.Insurer,
        'memberId'          : CONCAT(LEFT(v.Insurer, 2), N'-7745-', ABS(CHECKSUM(v.FullName)) % 9999),
        'groupId'           : CONCAT(N'GRP-', ABS(CHECKSUM(v.Insurer)) % 999, N'-', ABS(CHECKSUM(v.City)) % 9999),
        'planName'          : CONCAT(v.Insurer, N' Premier PPO'),
        'planType'          : N'PPO',
        'effectiveFrom'     : N'2024-01-01',
        'effectiveTo'       : N'2026-12-31',
        'primarySubscriber' : N'Self',
        'copay'             : JSON_OBJECT('primary': 25, 'specialist': 50, 'ED': 250),
        'deductibleUsd'     : 1500,
        'outOfPocketMaxUsd' : 5000,
        'networkStatus'     : N'InNetwork',
        'phone'             : N'+1-555-201-7700',
        'claimsAddress'     : N'PO Box 9000, Madison WI'
    )
FROM (VALUES
    (N'Newman Postal',          '1959-08-14', N'Male',   N'newman@waship.example',    N'+1-212-555-0142', N'New York',    N'10025', N'Vandelay Mutual'),
    (N'Babu Bhatt',             '1957-03-22', N'Male',   N'babu@dreamcafe.example',   N'+1-212-555-0118', N'New York',    N'10009', N'PennyPacker Health'),
    (N'Yev Kassem',             '1944-11-02', N'Male',   N'soup@kassem.example',      N'+1-212-555-0177', N'New York',    N'10019', N'Vandelay Mutual'),
    (N'Marla Penny',            '1963-05-30', N'Female', N'marla@example.com',        N'+1-212-555-0123', N'New York',    N'10023', N'Varnsen Health'),
    (N'Joe Davola',             '1961-02-17', N'Male',   N'joe@davola.example',       N'+1-212-555-0156', N'New York',    N'10001', N'PennyPacker Health'),
    (N'Jean-Paul Jean-Paul',    '1968-09-09', N'Male',   N'jp@marathon.example',      N'+1-212-555-0188', N'New York',    N'10018', N'Vandelay Mutual'),
    (N'Bob Sacamano',           '1955-07-04', N'Male',   N'bob@sacamano.example',     N'+1-212-555-0119', N'New York',    N'10003', N'Varnsen Health'),
    (N'Russell Dalrymple',      '1949-12-01', N'Male',   N'russell@nbc.example',      N'+1-212-555-0144', N'New York',    N'10020', N'PennyPacker Health'),
    (N'Tina Robbins',           '1962-04-26', N'Female', N'tina@example.com',         N'+1-212-555-0167', N'New York',    N'10021', N'Vandelay Mutual'),
    (N'Drake Stevens',          N'1965-10-14', N'Male',   N'thedrake@example.com',     N'+1-212-555-0102', N'New York',    N'10024', N'Varnsen Health'),
    (N'Pamela Rosenstein',      N'1969-01-23', N'Female', N'pamela@example.com',       N'+1-212-555-0185', N'New York',    N'10128', N'PennyPacker Health'),
    (N'James Bookman',          N'1942-06-08', N'Male',   N'jbookman@library.example', N'+1-212-555-0150', N'New York',    N'10016', N'Vandelay Mutual'),
    (N'George Steinbrenner',    N'1930-07-04', N'Male',   N'boss@yankees.example',     N'+1-212-555-0110', N'New York',    N'10017', N'Varnsen Health'),
    (N'Wendy Penewipple',       N'1967-12-30', N'Female', N'wendy@example.com',        N'+1-212-555-0173', N'New York',    N'10025', N'PennyPacker Health'),
    (N'Carol Leifer',           N'1964-03-15', N'Female', N'carol@example.com',        N'+1-212-555-0166', N'New York',    N'10011', N'Vandelay Mutual'),
    (N'Aaron Beriak',           N'1968-08-19', N'Male',   N'aaron@example.com',        N'+1-212-555-0181', N'New York',    N'10010', N'Varnsen Health'),
    (N'Art Vandelay',           N'1958-11-11', N'Male',   N'art@vandelay.example',     N'+1-212-555-0100', N'New York',    N'10003', N'PennyPacker Health'),
    (N'H. E. Pennypacker',      N'1956-04-04', N'Male',   N'hep@pennypacker.example',  N'+1-212-555-0101', N'New York',    N'10002', N'Vandelay Mutual'),
    (N'Kel Varnsen',            N'1959-05-05', N'Male',   N'kel@varnsen.example',      N'+1-212-555-0103', N'New York',    N'10004', N'Varnsen Health'),
    (N'Martin Van Nostrand',    N'1957-06-06', N'Male',   N'mvn@example.com',          N'+1-212-555-0104', N'New York',    N'10005', N'PennyPacker Health'),
    (N'Steven Snell',           N'1970-02-28', N'Male',   N'snell@example.com',        N'+1-212-555-0190', N'New York',    N'10128', N'Vandelay Mutual'),
    (N'Toby Bertini',           N'1965-09-12', N'Female', N'toby@example.com',         N'+1-212-555-0189', N'New York',    N'10006', N'Varnsen Health'),
    (N'Maureen Cain',           N'1968-07-21', N'Female', N'maureen@example.com',      N'+1-212-555-0175', N'New York',    N'10007', N'PennyPacker Health'),
    (N'Christie Maslo',         N'1971-01-17', N'Female', N'christie@example.com',     N'+1-212-555-0162', N'New York',    N'10008', N'Vandelay Mutual'),
    (N'Pierre Doucet',          N'1960-10-10', N'Male',   N'pierre@example.com',       N'+1-212-555-0152', N'New York',    N'10013', N'Varnsen Health'),
    (N'Earl Haffler',           N'1934-03-03', N'Male',   N'earl@example.com',         N'+1-212-555-0140', N'New York',    N'10026', N'PennyPacker Health'),
    (N'Jeffrey Fogel',          N'1962-08-08', N'Male',   N'jeffrey@parksdept.example', N'+1-212-555-0145', N'New York',   N'10027', N'Vandelay Mutual'),
    (N'Connie Pomerantz',       N'1966-11-19', N'Female', N'connie@example.com',       N'+1-212-555-0148', N'New York',    N'10028', N'Varnsen Health'),
    (N'Karen Hennigan',         N'1972-04-04', N'Female', N'karen@example.com',        N'+1-212-555-0163', N'New York',    N'10029', N'PennyPacker Health'),
    (N'Sandra Galbraith',       N'1969-12-24', N'Female', N'sandra@example.com',       N'+1-212-555-0192', N'New York',    N'10030', N'Vandelay Mutual')
) v(FullName, DateOfBirth, Sex, Email, Phone, City, PostalCode, Insurer);
GO

/* Generated bulk patients to reach @PatientCount total. */
DECLARE @Have INT = (SELECT COUNT(*) FROM clinical.Patient);
DECLARE @Need INT = 10000 - @Have;
PRINT CONCAT(N'--- clinical.Patient (generated bulk): need ', @Need, N' rows ---');

INSERT INTO clinical.Patient
    (MRN, FullName, DateOfBirth, Sex, Email, Phone, City, PostalCode, InsuranceJson)
SELECT
    CONCAT(N'WG-', RIGHT(CONCAT(N'000000', gs.value + @Have), 7)),
    CONCAT(
        CHOOSE(((gs.value * 7919)  % 24) + 1,
            N'Avery',N'Bailey',N'Cameron',N'Devon',N'Eden',N'Finley',
            N'Gray',N'Harper',N'Indigo',N'Jules',N'Kai',N'Lane',
            N'Micah',N'Noa',N'Oakley',N'Parker',N'Quinn',N'Reagan',
            N'Sage',N'Tate',N'Umber',N'Vail',N'Wren',N'Yael'),
        N' ',
        CHOOSE(((gs.value * 6151)  % 30) + 1,
            N'Adler',N'Barker',N'Conroy',N'Doyle',N'Esposito',N'Finch',
            N'Garber',N'Holcomb',N'Ingram',N'Jansen',N'Kobayashi',N'Lassiter',
            N'Maldonado',N'Nguyen',N'Okafor',N'Petrov',N'Quintero',N'Reyes',
            N'Sokolov',N'Tanaka',N'Underwood',N'Vasquez',N'Whitaker',N'Xiang',
            N'Yousef',N'Zheng',N'Brennan',N'Caldwell',N'Donnelly',N'Eberhardt')),
    DATEFROMPARTS(
        1930 + (ABS(CHECKSUM(NEWID())) % 80),
        1   + (ABS(CHECKSUM(NEWID())) %  12),
        1   + (ABS(CHECKSUM(NEWID())) %  28)),
    CASE WHEN gs.value % 2 = 0 THEN N'Female' ELSE N'Male' END,
    CONCAT(N'patient', gs.value + @Have, N'@example.com'),
    CONCAT(N'+1-212-555-',
           RIGHT(CONCAT(N'0000', ABS(CHECKSUM(NEWID())) % 10000), 4)),
    CHOOSE(((gs.value * 31) % 6) + 1,
           N'New York', N'Brooklyn', N'Queens', N'Bronx', N'Hoboken', N'Yonkers'),
    CONCAT(N'1', RIGHT(CONCAT(N'0000', ABS(CHECKSUM(NEWID())) % 10000), 4)),
    JSON_OBJECT(
        'insurer'           : CHOOSE(((gs.value * 17) % 4) + 1,
                                     N'Vandelay Mutual', N'PennyPacker Health',
                                     N'Varnsen Health',  N'Collier Health Plan'),
        'memberId'          : CONCAT(N'M-', RIGHT(CONCAT(N'00000', gs.value), 6)),
        'groupId'           : CONCAT(N'GRP-', (gs.value % 999), N'-',
                                     RIGHT(CONCAT(N'0000', gs.value % 9999), 4)),
        'planName'          : CHOOSE(((gs.value * 23) % 3) + 1,
                                     N'Premier PPO', N'Essential HMO', N'Bronze HDHP'),
        'planType'          : CHOOSE(((gs.value * 23) % 3) + 1, N'PPO', N'HMO', N'HDHP'),
        'effectiveFrom'     : N'2024-01-01',
        'effectiveTo'       : N'2026-12-31',
        'primarySubscriber' : N'Self',
        'copay'             : JSON_OBJECT('primary': 25, 'specialist': 50, 'ED': 250),
        'deductibleUsd'     : 1500,
        'outOfPocketMaxUsd' : 5000,
        'networkStatus'     : N'InNetwork',
        'phone'             : N'+1-555-201-7700',
        'claimsAddress'     : N'PO Box 9000, Madison WI'
    )
FROM GENERATE_SERIES(1, 9970) gs
WHERE gs.value <= @Need;
GO

/* ============================================================================
   6.  clinical.Allergy  (~15,000 — random subset of patients)
   ============================================================================ */
PRINT N'--- clinical.Allergy ---';
INSERT INTO clinical.Allergy (PatientId, Substance, Reaction, Severity)
SELECT TOP (15000)
    p.PatientId,
    CHOOSE(((p.PatientId * 7 + gs.value) % 10) + 1,
        N'Penicillin', N'Sulfa', N'Latex', N'Peanuts', N'Shellfish',
        N'Iodine contrast', N'NSAIDs', N'Codeine', N'Bee venom', N'Aspirin'),
    CHOOSE(((p.PatientId * 11 + gs.value) % 6) + 1,
        N'Hives', N'Anaphylaxis', N'Rash', N'Nausea', N'Swelling', N'Bronchospasm'),
    CHOOSE(((p.PatientId * 13 + gs.value) % 3) + 1, N'Mild', N'Moderate', N'Severe')
FROM clinical.Patient p
CROSS JOIN GENERATE_SERIES(1, 2) gs
ORDER BY ((p.PatientId * 1009 + gs.value) % 9973);
GO

/* ============================================================================
   7.  clinical.Encounter
       (a) 400 ACTIVE: one per bed, BedId 1..400, Status='Active'.
       (b) The rest DISCHARGED: BedId NULL, Status='Discharged'.
   ============================================================================ */
PRINT N'--- clinical.Encounter (active) ---';

DECLARE @BedCount   INT = (SELECT COUNT(*) FROM ops.Bed);
DECLARE @ProvCount  INT = (SELECT COUNT(*) FROM ops.Provider);
DECLARE @DeptCount  INT = (SELECT COUNT(*) FROM ops.Department);
DECLARE @PatCount   INT = (SELECT COUNT(*) FROM clinical.Patient);

/* Active encounters (one per bed) */
INSERT INTO clinical.Encounter
    (PatientId, DepartmentId, AttendingProviderId, BedId,
     EncounterType, AdmitTime, Status, IntakeJson)
SELECT
    /* spread patients/providers/depts deterministically */
    1 + ((b.BedId * 1019) % @PatCount)                              AS PatientId,
    1 + ((b.BedId * 7)    % @DeptCount)                             AS DepartmentId,
    1 + ((b.BedId * 31)   % @ProvCount)                             AS AttendingProviderId,
    b.BedId                                                         AS BedId,
    CHOOSE(((b.BedId * 17) % 3) + 1, N'Inpatient', N'ED', N'Inpatient') AS EncounterType,
    DATEADD(HOUR, -1 * ((b.BedId * 13) % 96), SYSUTCDATETIME())     AS AdmitTime,
    N'Active'                                                       AS Status,
    JSON_OBJECT(
        'chiefComplaint'    : CHOOSE(((b.BedId * 17) % 8) + 1,
            N'Chest tightness with intermittent radiation to left arm',
            N'Shortness of breath on exertion, 3-day onset',
            N'Acute right lower quadrant abdominal pain',
            N'Altered mental status, family-reported confusion x12h',
            N'Severe headache, photophobia, no trauma',
            N'Fever, productive cough, pleuritic chest pain',
            N'Lower extremity swelling and erythema, possible DVT',
            N'Persistent vomiting and dehydration, 24h'),
        'esiLevel'          : 1 + ((b.BedId * 7) % 4),
        'arrivalMode'       : CHOOSE(((b.BedId * 11) % 3) + 1,
                                     N'Walk-in', N'EMS', N'Transfer'),
        'triageVitals'      : JSON_OBJECT(
            'heartRate'      : 60 + ((b.BedId * 7) % 60),
            'bloodPressure'  : JSON_OBJECT(
                'systolic'  : 100 + ((b.BedId * 13) % 60),
                'diastolic' : 60  + ((b.BedId * 11) % 30)),
            'spO2'           : 90 + ((b.BedId * 5)  % 9),
            'temperatureC'   : 36.5 + (((b.BedId * 3) % 30) / 10.0),
            'respRate'       : 12 + ((b.BedId * 5)  % 12)),
        'painScore'         : ((b.BedId * 7) % 11),
        'allergiesAtIntake' : JSON_ARRAY(N'Penicillin', N'Latex'),
        'currentMedications': JSON_ARRAY(
                                  N'Lisinopril 10mg daily',
                                  N'Atorvastatin 40mg nightly',
                                  N'Aspirin 81mg daily'),
        'pastMedicalHistory': JSON_ARRAY(N'Hypertension', N'Hyperlipidemia',
                                         N'Type 2 Diabetes'),
        'socialHistory'     : JSON_OBJECT(
            'tobacco' : CHOOSE(((b.BedId * 7) % 3) + 1,
                                N'Never', N'Former, quit 2018', N'Current 1ppd'),
            'alcohol' : N'Social',
            'drugs'   : N'Denied'),
        'lastOralIntake'    : N'2026-11-04T18:30:00Z',
        'advanceDirectives' : N'Full code',
        'triageNurseId'     : 47,
        'triageNotes'       : N'Patient ambulatory; cooperative. Cardiac monitor and ECG within 10 min per ED protocol.'
    )
FROM ops.Bed b;

PRINT N'--- clinical.Encounter (discharged) ---';

/* Local scale knob — keep in sync with the other two @Scale declarations
   in this file (Appointment and Observation batches). */
DECLARE @Scale          FLOAT = 1.0;
DECLARE @EncounterCount INT   = CAST(40000 * @Scale AS INT);

/* Discharged encounters — backfill to @EncounterCount total. */
DECLARE @Active INT = (SELECT COUNT(*) FROM clinical.Encounter);
DECLARE @Discharged INT = @EncounterCount - @Active;
PRINT CONCAT(N'    active = ', @Active, N', discharged to add = ', @Discharged);

INSERT INTO clinical.Encounter
    (PatientId, DepartmentId, AttendingProviderId, BedId,
     EncounterType, AdmitTime, DischargeTime, Status, IntakeJson)
SELECT
    1 + ((gs.value * 4001) % @PatCount)                                AS PatientId,
    1 + ((gs.value * 17)   % @DeptCount)                               AS DepartmentId,
    1 + ((gs.value * 23)   % @ProvCount)                               AS AttendingProviderId,
    NULL                                                               AS BedId,
    CHOOSE(((gs.value * 5) % 3) + 1, N'Inpatient', N'ED', N'Outpatient') AS EncounterType,
    DATEADD(DAY, -1 * (1 + ((gs.value * 7) % 720)), SYSUTCDATETIME())  AS AdmitTime,
    DATEADD(DAY,
            -1 * (1 + ((gs.value * 7) % 720))
              + (1 + ((gs.value * 3) % 6)),                            -- 1-7 day stay
            SYSUTCDATETIME())                                           AS DischargeTime,
    N'Discharged'                                                       AS Status,
    JSON_OBJECT(
        'chiefComplaint': CHOOSE(((gs.value * 7) % 5) + 1,
            N'Routine follow-up', N'Post-operative check',
            N'Chronic back pain flare', N'Hypertension management',
            N'Diabetes follow-up'),
        'esiLevel'      : 1 + ((gs.value * 7) % 4),
        'arrivalMode'   : N'Walk-in',
        'triageVitals'  : JSON_OBJECT(
            'heartRate'      : 60 + ((gs.value * 7) % 40),
            'bloodPressure'  : JSON_OBJECT(
                'systolic' : 110 + ((gs.value * 13) % 40),
                'diastolic': 65  + ((gs.value * 11) % 25)),
            'spO2'           : 95 + ((gs.value * 5) % 5),
            'temperatureC'   : 36.5 + (((gs.value * 3) % 20) / 10.0),
            'respRate'       : 12 + ((gs.value * 5) % 8))
    )
FROM GENERATE_SERIES(1, 80000) gs
WHERE gs.value <= @Discharged;
GO

/* Mark beds with an active encounter as Occupied. */
PRINT N'--- ops.Bed mark Occupied for active encounters ---';
UPDATE b
SET BedStatus = N'Occupied'
FROM ops.Bed b
WHERE EXISTS (
    SELECT 1 FROM clinical.Encounter e
    WHERE e.BedId = b.BedId AND e.Status = N'Active'
);
GO

/* ============================================================================
   8.  ops.Appointment  (~120,000)
   ============================================================================ */
PRINT N'--- ops.Appointment ---';
DECLARE @Scale            FLOAT = 1.0;
DECLARE @AppointmentCount INT   = CAST(120000 * @Scale AS INT);
DECLARE @PatCount  INT = (SELECT COUNT(*) FROM clinical.Patient);
DECLARE @ProvCount INT = (SELECT COUNT(*) FROM ops.Provider);
DECLARE @DeptCount INT = (SELECT COUNT(*) FROM ops.Department);

INSERT INTO ops.Appointment
    (PatientId, ProviderId, DepartmentId, ScheduledStart, ScheduledEnd, Status)
SELECT
    1 + ((gs.value * 1009) % @PatCount),
    1 + ((gs.value * 41)   % @ProvCount),
    1 + ((gs.value * 7)    % @DeptCount),
    DATEADD(MINUTE, ((gs.value * 17) % 1440) - 360,
        DATEADD(DAY, ((gs.value * 11) % 730) - 365, SYSUTCDATETIME())),
    DATEADD(MINUTE, ((gs.value * 17) % 1440) - 360 + 30,
        DATEADD(DAY, ((gs.value * 11) % 730) - 365, SYSUTCDATETIME())),
    CHOOSE(((gs.value * 13) % 4) + 1,
           N'Scheduled', N'Completed', N'Cancelled', N'NoShow')
FROM GENERATE_SERIES(1, 120000) gs
WHERE gs.value <= @AppointmentCount;
GO

/* ============================================================================
   9.  clinical.Diagnosis  (~80,000 — 2 per encounter average)
   ============================================================================ */
PRINT N'--- clinical.Diagnosis ---';
INSERT INTO clinical.Diagnosis (EncounterId, IcdCode, Description, DiagnosedById)
SELECT
    e.EncounterId,
    CHOOSE(((e.EncounterId * 7 + gs.value) % 10) + 1,
           N'I10',   N'E11.9', N'I50.9', N'J18.9', N'N39.0',
           N'K35.80',N'R07.9', N'R55',   N'I63.9', N'J44.9'),
    CHOOSE(((e.EncounterId * 7 + gs.value) % 10) + 1,
           N'Essential hypertension',
           N'Type 2 diabetes mellitus without complications',
           N'Heart failure, unspecified',
           N'Pneumonia, unspecified organism',
           N'Urinary tract infection, site not specified',
           N'Acute appendicitis without rupture',
           N'Chest pain, unspecified',
           N'Syncope and collapse',
           N'Cerebral infarction, unspecified',
           N'Chronic obstructive pulmonary disease, unspecified'),
    e.AttendingProviderId
FROM clinical.Encounter e
CROSS JOIN GENERATE_SERIES(1, 2) gs;
GO

/* ============================================================================
   10. clinical.ClinicalNote  (~50,000 — ~1.25 per encounter; ~1-2 KB NoteText)
   ============================================================================ */
PRINT N'--- clinical.ClinicalNote ---';
INSERT INTO clinical.ClinicalNote
    (EncounterId, AuthorProviderId, NoteType, NoteText)
SELECT
    e.EncounterId,
    e.AttendingProviderId,
    CHOOSE(((e.EncounterId + gs.value) % 3) + 1,
           N'Progress', N'Consult', N'Discharge'),
    CONCAT(
        N'Subjective: Patient reports ', CHOOSE(((e.EncounterId * 3 + gs.value) % 6) + 1,
            N'persistent retrosternal chest discomfort radiating to the left arm and jaw, ',
            N'progressive dyspnea with exertion over the past three days, ',
            N'sharp right lower quadrant abdominal pain with associated nausea and anorexia, ',
            N'subjective fevers, chills, and productive cough with green sputum, ',
            N'lightheadedness with one episode of near-syncope while ambulating, ',
            N'new lower extremity swelling and warmth with mild calf tenderness, '),
        N'denying recent trauma, with associated mild diaphoresis and a pain score of ',
        CAST(((e.EncounterId * 7) % 10) + 1 AS NVARCHAR(2)),
        N' out of 10. Patient endorses adherence to home medications including ',
        N'lisinopril, atorvastatin, and low-dose aspirin. No new medications or supplements. ',
        N'Family history significant for premature coronary artery disease. ',
        CHAR(13), CHAR(10),
        N'Objective: T 37.', CAST(((e.EncounterId * 3) % 9) AS NVARCHAR(1)),
        N'C, HR ', CAST(60 + ((e.EncounterId * 7) % 50) AS NVARCHAR(3)),
        N', BP ', CAST(110 + ((e.EncounterId * 13) % 50) AS NVARCHAR(3)),
        N'/', CAST(65 + ((e.EncounterId * 11) % 25) AS NVARCHAR(3)),
        N', RR ', CAST(12 + ((e.EncounterId * 5) % 10) AS NVARCHAR(3)),
        N', SpO2 ', CAST(92 + ((e.EncounterId * 3) % 7) AS NVARCHAR(3)),
        N'% on room air. Patient appears comfortable, in no acute distress. ',
        N'HEENT atraumatic and normocephalic, mucous membranes moist. Neck supple, no JVD, no lymphadenopathy. ',
        N'Cardiac auscultation reveals regular rate and rhythm with no murmurs, rubs, or gallops. ',
        N'Pulmonary exam with clear breath sounds bilaterally, no rales or wheezing. ',
        N'Abdomen soft, non-tender, non-distended with normoactive bowel sounds. ',
        N'Extremities warm and well perfused with 2+ pulses bilaterally and no edema. ',
        N'Neurologic exam grossly intact, alert and oriented to person, place, time, and situation. ',
        CHAR(13), CHAR(10),
        N'Assessment: ',
        CHOOSE(((e.EncounterId * 11) % 5) + 1,
            N'Acute coronary syndrome ruled out by serial troponins; likely musculoskeletal chest pain. ',
            N'Community-acquired pneumonia, lower lobe, responding to empiric antibiotics. ',
            N'Acute appendicitis, post-operative day 1, recovering well after laparoscopic appendectomy. ',
            N'Symptomatic anemia, likely iron-deficiency, transfusion requirement nil at this time. ',
            N'Decompensated heart failure with reduced ejection fraction, diuresing on IV furosemide. '),
        N'Pertinent comorbidities including hypertension, hyperlipidemia, and type 2 diabetes well controlled. ',
        N'No acute neurologic or surgical concerns identified during today''s evaluation. ',
        CHAR(13), CHAR(10),
        N'Plan: Continue current medical management with telemetry monitoring overnight. ',
        N'Repeat basic metabolic panel and complete blood count in the morning. ',
        N'Cardiology consultation has been placed for risk stratification and outpatient follow-up. ',
        N'Physical therapy evaluation for safe ambulation prior to discharge planning. ',
        N'Patient and family educated on medication reconciliation, dietary sodium restriction, ',
        N'and the importance of follow-up with primary care within seven days of discharge. ',
        N'Discharge anticipated within 48 hours pending clinical stability and home services arrangement. '
    )
FROM clinical.Encounter e
CROSS JOIN GENERATE_SERIES(1, 2) gs
WHERE ((e.EncounterId + gs.value) % 4) <> 0;   -- ~1.25 notes per encounter
GO

/* ============================================================================
   11. clinical.MedicationOrder  (~100,000 — 2.5 per encounter average)
   ============================================================================ */
PRINT N'--- clinical.MedicationOrder ---';
INSERT INTO clinical.MedicationOrder
    (EncounterId, PatientId, MedicationName, Dose, Route, OrderedById, OrderedAt)
SELECT
    e.EncounterId,
    e.PatientId,
    CHOOSE(((e.EncounterId * 7 + gs.value) % 12) + 1,
        N'Lisinopril', N'Atorvastatin', N'Aspirin', N'Metoprolol',
        N'Furosemide', N'Insulin glargine', N'Ceftriaxone', N'Azithromycin',
        N'Ondansetron', N'Acetaminophen', N'Heparin', N'Pantoprazole'),
    CHOOSE(((e.EncounterId * 11 + gs.value) % 6) + 1,
           N'10 mg', N'40 mg', N'81 mg', N'1 g', N'4 mg', N'5000 units'),
    CHOOSE(((e.EncounterId * 13 + gs.value) % 4) + 1,
           N'PO', N'IV', N'SC', N'IM'),
    e.AttendingProviderId,
    DATEADD(MINUTE, gs.value * 60, e.AdmitTime)
FROM clinical.Encounter e
CROSS JOIN GENERATE_SERIES(1, 3) gs
WHERE ((e.EncounterId * 5 + gs.value) % 6) < 5;   -- ~2.5 per encounter
GO

/* ============================================================================
   12. clinical.LabResult  (~200,000 — 5 per encounter average)
   ============================================================================ */
PRINT N'--- clinical.LabResult ---';
INSERT INTO clinical.LabResult
    (EncounterId, PatientId, OrderedById, TestName, CollectedAt, ResultedAt, ResultJson, Status)
SELECT
    e.EncounterId,
    e.PatientId,
    e.AttendingProviderId,
    CHOOSE(((e.EncounterId * 7 + gs.value) % 6) + 1,
           N'CBC', N'BMP', N'CMP', N'Troponin I', N'Lipid Panel', N'TSH'),
    DATEADD(MINUTE, gs.value * 30,   e.AdmitTime),
    DATEADD(MINUTE, gs.value * 30 + 45, e.AdmitTime),
    JSON_OBJECT(
        'panel'        : CHOOSE(((e.EncounterId * 7 + gs.value) % 6) + 1,
                                N'CBC', N'BMP', N'CMP',
                                N'Troponin I', N'Lipid Panel', N'TSH'),
        'specimen'     : N'Whole blood, EDTA',
        'instrument'   : N'Sysmex XN-1000',
        'performedBy'  : CONCAT(N'tech-', (gs.value * 7) % 999),
        'verifiedBy'   : CONCAT(N'MT-',  (gs.value * 11) % 99),
        'analytes'     : JSON_ARRAY(
            JSON_OBJECT('name': N'WBC',   'value': 7.4 + (((e.EncounterId * 3 + gs.value) % 30) / 10.0),
                        'unit': N'K/uL', 'refLow': 4.5,  'refHigh': 11.0),
            JSON_OBJECT('name': N'RBC',   'value': 4.6 + (((e.EncounterId * 5 + gs.value) % 15) / 10.0),
                        'unit': N'M/uL', 'refLow': 4.5,  'refHigh': 5.9),
            JSON_OBJECT('name': N'HGB',   'value': 13 + (((e.EncounterId * 7 + gs.value) % 40) / 10.0),
                        'unit': N'g/dL', 'refLow': 12.0, 'refHigh': 17.0),
            JSON_OBJECT('name': N'HCT',   'value': 40 + (((e.EncounterId * 11 + gs.value) % 80) / 10.0),
                        'unit': N'%',    'refLow': 36.0, 'refHigh': 51.0),
            JSON_OBJECT('name': N'PLT',   'value': 200 + ((e.EncounterId * 13 + gs.value) % 150),
                        'unit': N'K/uL', 'refLow': 150,  'refHigh': 400),
            JSON_OBJECT('name': N'GLU',   'value': 80 + ((e.EncounterId * 17 + gs.value) % 80),
                        'unit': N'mg/dL','refLow': 70,   'refHigh': 100),
            JSON_OBJECT('name': N'BUN',   'value': 10 + ((e.EncounterId * 19 + gs.value) % 20),
                        'unit': N'mg/dL','refLow': 7,    'refHigh': 20),
            JSON_OBJECT('name': N'CR',    'value': 0.9 + (((e.EncounterId * 23 + gs.value) % 10) / 10.0),
                        'unit': N'mg/dL','refLow': 0.6,  'refHigh': 1.3)
        )
    ),
    N'Resulted'
FROM clinical.Encounter e
CROSS JOIN GENERATE_SERIES(1, 5) gs;
GO

/* ============================================================================
   13. clinical.Observation  (~108M — the size anchor)
       Generated in batches of @BatchEncounters encounters to keep log apply
       moving and stay within reasonable memory/log governance. On a 4 vCore
       HS_Gen5 primary expect ~5-15 min total at @Scale = 1.0.
   ============================================================================ */
PRINT N'--- clinical.Observation (batched) ---';

DECLARE @Scale      FLOAT = 1.0;
DECLARE @ObsPerEnc  INT   = CAST(2700 * @Scale AS INT);  -- 5 types × 540 samples
DECLARE @BatchEncounters INT = 1000;
DECLARE @MinEnc INT, @MaxEnc INT, @CurEnc INT, @Batch INT = 0;
SELECT @MinEnc = MIN(EncounterId), @MaxEnc = MAX(EncounterId) FROM clinical.Encounter;
SET @CurEnc = @MinEnc;

WHILE @CurEnc <= @MaxEnc
BEGIN
    SET @Batch = @Batch + 1;

    INSERT INTO clinical.Observation
        (EncounterId, PatientId, RecordedAt, ObservationType, ValueNumeric, Unit)
    SELECT
        e.EncounterId,
        e.PatientId,
        DATEADD(MINUTE, gs.value * 15, e.AdmitTime),
        t.ObservationType,
        CASE t.ObservationType
            WHEN N'HeartRate'     THEN  60 + ((gs.value + e.EncounterId * 3) % 60)
            WHEN N'BloodPressure' THEN 110 + ((gs.value + e.EncounterId * 5) % 50)
            WHEN N'SpO2'          THEN  90 + ((gs.value + e.EncounterId * 7) % 10)
            WHEN N'Temperature'   THEN  36.5 + (((gs.value + e.EncounterId * 11) % 25) / 10.0)
            WHEN N'RespRate'      THEN  12 + ((gs.value + e.EncounterId * 13) % 12)
        END,
        t.Unit
    FROM clinical.Encounter e
    CROSS JOIN GENERATE_SERIES(1, @ObsPerEnc / 5) gs
    CROSS JOIN (VALUES
        (N'HeartRate',     N'bpm'),
        (N'BloodPressure', N'mmHg'),
        (N'SpO2',          N'%'),
        (N'Temperature',   N'C'),
        (N'RespRate',      N'/min')
    ) t(ObservationType, Unit)
    WHERE e.EncounterId BETWEEN @CurEnc AND @CurEnc + @BatchEncounters - 1;

    PRINT CONCAT(N'    batch ', @Batch,
                 N' done at ', CONVERT(NVARCHAR(30), SYSUTCDATETIME(), 126));
    SET @CurEnc = @CurEnc + @BatchEncounters;
END;
GO

/* ============================================================================
   Final summary
   ============================================================================ */
PRINT N'--- Row counts ---';
SELECT N'ops.Department'            AS TableName, COUNT(*) AS [RowCount] FROM ops.Department
UNION ALL SELECT N'ops.Unit',                COUNT(*) FROM ops.Unit
UNION ALL SELECT N'ops.Bed',                 COUNT(*) FROM ops.Bed
UNION ALL SELECT N'ops.Provider',            COUNT(*) FROM ops.Provider
UNION ALL SELECT N'ops.Appointment',         COUNT(*) FROM ops.Appointment
UNION ALL SELECT N'clinical.Patient',        COUNT(*) FROM clinical.Patient
UNION ALL SELECT N'clinical.Allergy',        COUNT(*) FROM clinical.Allergy
UNION ALL SELECT N'clinical.Encounter',      COUNT(*) FROM clinical.Encounter
UNION ALL SELECT N'clinical.Diagnosis',      COUNT(*) FROM clinical.Diagnosis
UNION ALL SELECT N'clinical.ClinicalNote',   COUNT(*) FROM clinical.ClinicalNote
UNION ALL SELECT N'clinical.MedicationOrder',COUNT(*) FROM clinical.MedicationOrder
UNION ALL SELECT N'clinical.LabResult',      COUNT(*) FROM clinical.LabResult
UNION ALL SELECT N'clinical.Observation',    COUNT(*) FROM clinical.Observation;
GO

PRINT N'--- Approximate space used ---';
SELECT
    SUM(reserved_page_count) * 8.0 / 1024.0 / 1024.0 AS ReservedGB,
    SUM(used_page_count)     * 8.0 / 1024.0 / 1024.0 AS UsedGB
FROM sys.dm_db_partition_stats;
GO

PRINT N'Seed complete.';
GO
