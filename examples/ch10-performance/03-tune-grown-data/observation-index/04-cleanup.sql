/*=============================================================================
  Chapter 10, Demo 3: evaluate the Chapter 7 ValueNumeric recommendation.
  04-cleanup.sql - drop ONLY the index this example created.

  Safe to run any time and safe to repeat. It touches no data and no other
  index. Dropping the index frees its pages; Hyperscale allocated storage
  does not shrink on its own (see the Chapter 10 README).
=============================================================================*/
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
SET NOCOUNT ON;

DROP INDEX IF EXISTS IX_Observation_ValueNumeric_Ch10 ON clinical.Observation;

SELECT CONCAT(N'CH10OBS_CLEAN|',
    CASE WHEN EXISTS (SELECT 1 FROM sys.indexes
                      WHERE object_id = OBJECT_ID(N'clinical.Observation')
                        AND name = N'IX_Observation_ValueNumeric_Ch10')
         THEN N'present' ELSE N'absent' END);
GO
