/* ============================================================================
   Azure SQL Hyperscale Unveiled — Chapter 2
   verify-data.sql : verify the seed landed — row counts, reserved size, and
                     automated PASS/FAIL checks that raise an error if the seed
                     is incomplete (a failed/partial seed can't pass silently).
   Run order       : after 05-seed.sql.  Set @Scale (in the checks block) to
                     match the @Scale used in 05-seed.sql (default 1.0).

   Confirms the ~10 GB through-line dataset is in place before later chapters
   build on it. Pair with connect-and-verify.sql (which proves the tier).

   These DMVs are used informally for verification here; the full observability
   toolkit (Query Store, Extended Events, Azure Monitor, RBPEX signals) is
   taught in Ch 7.
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

PRINT N'-- Row counts per table (clustered/heap base rows) ------------------';
SELECT
    s.name + N'.' + t.name                         AS TableName,
    SUM(ps.row_count)                              AS [RowCount],
    SUM(ps.reserved_page_count) * 8.0 / 1024       AS ReservedMB
FROM sys.dm_db_partition_stats ps
JOIN sys.tables  t ON t.object_id = ps.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE ps.index_id IN (0, 1)
GROUP BY s.name, t.name
ORDER BY ReservedMB DESC;
GO

PRINT N'-- Total reserved size (expect a little over 10 GB) -----------------';
SELECT
    SUM(reserved_page_count) * 8.0 / 1024 / 1024   AS TotalReservedGB
FROM sys.dm_db_partition_stats;
GO

/* ---------------------------------------------------------------------------
   Automated verification — PASS/FAIL. Detects a failed or partial seed and
   RAISERRORs (red in SSMS) if anything is wrong, so a bad seed can't slip by.
   Set @Scale to match the value used in 05-seed.sql (1.0 = full seed).
   Row counts come from sys.dm_db_partition_stats (fast, approximate), so the
   floors are deliberately generous to tolerate that approximation.
--------------------------------------------------------------------------- */
PRINT N'-- Verification checks (PASS/FAIL) ----------------------------------';
GO
DECLARE @Scale FLOAT = 1.0;   -- MATCH the @Scale used in 05-seed.sql

IF OBJECT_ID('tempdb..#rc') IS NOT NULL DROP TABLE #rc;
SELECT s.name AS sch, t.name AS tbl, SUM(ps.row_count) AS rows_
INTO #rc
FROM sys.dm_db_partition_stats ps
JOIN sys.tables   t ON t.object_id = ps.object_id
JOIN sys.schemas  s ON s.schema_id = t.schema_id
WHERE ps.index_id IN (0, 1) AND s.name IN (N'clinical', N'ops')
GROUP BY s.name, t.name;

DECLARE @results TABLE (CheckName NVARCHAR(60), Expected NVARCHAR(40), Actual NVARCHAR(40), Status NVARCHAR(6));

DECLARE @nTables INT = (SELECT COUNT(*) FROM #rc);
INSERT @results VALUES (N'Base tables present', N'13',
    CONVERT(NVARCHAR(40), @nTables), IIF(@nTables = 13, N'PASS', N'FAIL'));

DECLARE @nEmpty INT = (SELECT COUNT(*) FROM #rc WHERE rows_ = 0);
INSERT @results VALUES (N'Tables with 0 rows', N'0',
    CONVERT(NVARCHAR(40), @nEmpty), IIF(@nEmpty = 0, N'PASS', N'FAIL'));

DECLARE @obs BIGINT = (SELECT ISNULL(MAX(rows_), 0) FROM #rc WHERE sch = N'clinical' AND tbl = N'Observation');
DECLARE @obsMin BIGINT = CONVERT(BIGINT, 90000000 * @Scale);
INSERT @results VALUES (N'Observation rows (anchor)', N'>= ' + CONVERT(NVARCHAR(40), @obsMin),
    CONVERT(NVARCHAR(40), @obs), IIF(@obs >= @obsMin, N'PASS', N'FAIL'));

DECLARE @gb DECIMAL(10,2) = (SELECT CONVERT(DECIMAL(10,2), SUM(reserved_page_count) * 8.0 / 1024 / 1024) FROM sys.dm_db_partition_stats);
DECLARE @gbMin DECIMAL(10,2) = CONVERT(DECIMAL(10,2), 10.0 * @Scale);
INSERT @results VALUES (N'Total reserved GB', N'>= ' + CONVERT(NVARCHAR(40), @gbMin),
    CONVERT(NVARCHAR(40), @gb), IIF(@gb >= @gbMin, N'PASS', N'FAIL'));

SELECT CheckName, Expected, Actual, Status FROM @results;

IF EXISTS (SELECT 1 FROM @results WHERE Status = N'FAIL')
BEGIN
    DECLARE @msg NVARCHAR(2048) =
        N'SEED VERIFICATION FAILED: ' + (SELECT STRING_AGG(CheckName, N'; ') FROM @results WHERE Status = N'FAIL');
    RAISERROR(@msg, 16, 1);
END
ELSE
    PRINT N'ALL CHECKS PASSED -- seed verified (13 tables populated, anchor + size OK).';
GO
