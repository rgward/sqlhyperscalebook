/*=============================================================================
  Chapter 10, Demo 3: evaluate the Chapter 7 ValueNumeric recommendation.
  01-measure-read.sql - run the Chapter 7 scan query and report its I/O and time.

  The query is the one Chapter 7's performance demo runs (observe-scan.sql),
  with its own marker so Query Store keeps the two apart. Run it before and
  after 03-create-index.sql and compare logical reads and CPU time.

  Read-only. This script creates, changes, and deletes nothing.
=============================================================================*/
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT
    /* CH10_OBSERVATION_READ */
    ObservationType,
    ObservationCount = COUNT_BIG(*),
    AverageValue = AVG(ValueNumeric)
FROM clinical.Observation
WHERE ValueNumeric BETWEEN 90 AND 110
GROUP BY ObservationType
OPTION (RECOMPILE);

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

/* Did the demo index serve the query? Zeros before it exists. */
SELECT CONCAT(
    N'CH10OBS_USAGE|',
    COALESCE(SUM(us.user_seeks), 0), N'|',
    COALESCE(SUM(us.user_scans), 0))
FROM sys.indexes AS i
LEFT JOIN sys.dm_db_index_usage_stats AS us
    ON us.database_id = DB_ID()
   AND us.object_id = i.object_id
   AND us.index_id = i.index_id
WHERE i.object_id = OBJECT_ID(N'clinical.Observation')
  AND i.name = N'IX_Observation_ValueNumeric_Ch10';
GO
