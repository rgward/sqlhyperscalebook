/*=============================================================================
  Chapter 10, Demo 3: evaluate the Chapter 7 ValueNumeric recommendation.
  02-measure-write.sql - measure what new observations cost to write.

  Calls clinical.RecordVitals 500 times inside ONE transaction, reads how much
  transaction log that transaction generated, then ROLLS IT BACK. No rows
  persist. Run it before and after 03-create-index.sql: every extra index on
  clinical.Observation is another structure each insert must also write.
=============================================================================*/
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Rows        INT = 500,
        @i           INT = 0,
        @EncounterId INT,
        @Started     DATETIME2(7),
        @ElapsedMs   BIGINT,
        @LogBytes    BIGINT;

SELECT TOP (1) @EncounterId = EncounterId
FROM clinical.Encounter
ORDER BY EncounterId DESC;

IF @EncounterId IS NULL
    THROW 51070, 'No encounters found. Run the Chapter 2 seed first.', 1;

BEGIN TRANSACTION;

SET @Started = SYSUTCDATETIME();
WHILE @i < @Rows
BEGIN
    EXEC clinical.RecordVitals
        @EncounterId     = @EncounterId,
        @ObservationType = N'HeartRate',
        @ValueNumeric    = 98,
        @Unit            = N'bpm';
    SET @i += 1;
END;
SET @ElapsedMs = DATEDIFF_BIG(MILLISECOND, @Started, SYSUTCDATETIME());

SELECT @LogBytes = dt.database_transaction_log_bytes_used
FROM sys.dm_tran_database_transactions AS dt
WHERE dt.transaction_id = CURRENT_TRANSACTION_ID()
  AND dt.database_id = DB_ID();

ROLLBACK TRANSACTION;

SELECT CONCAT(N'CH10OBS_WRITE|', @Rows, N'|', COALESCE(@LogBytes, 0), N'|', @ElapsedMs);
GO
