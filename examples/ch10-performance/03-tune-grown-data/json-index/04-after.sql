/* ============================================================================
    Chapter 10, Demo 3: repeat the identical JSON predicate after the index.
    The script returns actual Showplan XML automatically for comparison.

    The query runs TWICE. The first run compiles a new plan against the new
    index; the second is the warm run the book reports ("24 total reads, under
    1 ms warm execution"). run-demo.ps1 reports both.
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
SET STATISTICS XML ON;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.json_indexes
    WHERE object_id = OBJECT_ID(N'clinical.LabResultArchive')
      AND name = N'JX_LabResultArchive_ResultJson'
)
    THROW 51014, 'Run 03-create-index.sql before capturing the indexed result.', 1;
GO

-- First run: includes compiling the plan that uses the new JSON index.
SELECT
    SpecimenId = JSON_VALUE(ResultJson, '$.specimenId'),
    WbcValue = JSON_VALUE(ResultJson, '$.wbcValue' RETURNING DECIMAL(4, 1)),
    Flags = JSON_QUERY(ResultJson, '$.flags')
FROM clinical.LabResultArchive
WHERE JSON_CONTAINS(ResultJson, N'critical', '$.flags[*]') = 1
OPTION (MAXDOP 1);
GO

-- Warm run: the identical statement, reusing the cached plan and pages.
SELECT
    SpecimenId = JSON_VALUE(ResultJson, '$.specimenId'),
    WbcValue = JSON_VALUE(ResultJson, '$.wbcValue' RETURNING DECIMAL(4, 1)),
    Flags = JSON_QUERY(ResultJson, '$.flags')
FROM clinical.LabResultArchive
WHERE JSON_CONTAINS(ResultJson, N'critical', '$.flags[*]') = 1
OPTION (MAXDOP 1);
GO

SET STATISTICS XML OFF;
SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO
