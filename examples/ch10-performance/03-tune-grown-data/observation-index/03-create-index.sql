/*=============================================================================
  Chapter 10, Demo 3: evaluate the Chapter 7 ValueNumeric recommendation.
  03-create-index.sql - build the index Query Store recommended in Chapter 7.

  Key column ValueNumeric (the inequality column), INCLUDE ObservationType
  (the included column). Built ONLINE, so reads and writes continue during the
  build. On the ~108-million-row clinical.Observation this takes minutes and
  adds billed storage until 04-cleanup.sql drops it.

  Reports the build time, the index size, and the table's own size.
=============================================================================*/
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
SET NOCOUNT ON;

DECLARE @Started DATETIME2(7) = SYSUTCDATETIME();

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID(N'clinical.Observation')
                 AND name = N'IX_Observation_ValueNumeric_Ch10')
BEGIN
    CREATE NONCLUSTERED INDEX IX_Observation_ValueNumeric_Ch10
        ON clinical.Observation (ValueNumeric)
        INCLUDE (ObservationType)
        WITH (ONLINE = ON);
END;

DECLARE @ElapsedMs BIGINT = DATEDIFF_BIG(MILLISECOND, @Started, SYSUTCDATETIME());

DECLARE @IndexMB DECIMAL(19, 1) = (
    SELECT CAST(SUM(ps.used_page_count) * 8.0 / 1024 AS DECIMAL(19, 1))
    FROM sys.dm_db_partition_stats AS ps
    JOIN sys.indexes AS i
        ON i.object_id = ps.object_id
       AND i.index_id = ps.index_id
    WHERE i.object_id = OBJECT_ID(N'clinical.Observation')
      AND i.name = N'IX_Observation_ValueNumeric_Ch10');

DECLARE @TableMB DECIMAL(19, 1) = (
    SELECT CAST(SUM(ps.used_page_count) * 8.0 / 1024 AS DECIMAL(19, 1))
    FROM sys.dm_db_partition_stats AS ps
    WHERE ps.object_id = OBJECT_ID(N'clinical.Observation')
      AND ps.index_id IN (0, 1));

SELECT CONCAT(N'CH10OBS_INDEX|', @ElapsedMs, N'|', COALESCE(@IndexMB, 0), N'|', COALESCE(@TableMB, 0));
GO
