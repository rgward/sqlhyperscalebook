/* ============================================================================
   Inside Azure SQL Hyperscale — Chapter 2
   verify-data.sql : verify the seed landed — row counts and reserved size.
   Run order       : after 05-seed.sql.

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
