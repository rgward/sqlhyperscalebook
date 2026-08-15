/* ============================================================================
   Ward General Hospital — Hyperscale developer demo
   07-vector-index.sql : AI layer 2 of 3 — the DiskANN vector index
   Run order           : after 06-ai-embeddings.sql, before 08-ai-assistance.sql

   One statement, its own file. The index is separable from the vectors it
   covers: 06 spends hours of metered model calls building the embeddings and
   you never want to repeat that by accident, whereas this index is quick to
   build and safe to throw away. Keeping them apart means you can rebuild the
   index — after a bulk reload, or to change METRIC — without going anywhere
   near the corpus.

   Why a DiskANN vector index here (Hyperscale close):
     The latest-version DiskANN index on Azure SQL Database is UPDATEABLE —
     INSERT/UPDATE/DELETE keep the index current in real time, so the app can
     write new notes and have them become searchable with no rebuild and no
     read-only window. Earlier index versions (and the TOP_N parameter) are
     deprecated; this example uses SELECT TOP (N) WITH APPROXIMATE only.
     ref: https://learn.microsoft.com/azure/azure-sql/database/doc-changes-updates-release-notes-whats-new  (accessed 2026-07-20)

   Because the index is updateable, re-running this script after adding notes
   is unnecessary — new rows are indexed as they land.

   PREREQUISITES:
     * 06-ai-embeddings.sql already run, with at least 100 embedded notes.

   No placeholders to replace in this file.

   All data created by these scripts is fully synthetic. No real PHI.
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

/* DiskANN needs at least 100 rows to build. Below that, VECTOR_SEARCH still
   works via exact scan (instant on small tables), so both procedures are
   functional either way — the index just makes them scale. */
PRINT '=== Creating DiskANN vector index (if >= 100 notes) ===';
GO

DECLARE @rows INT = (SELECT COUNT(*) FROM clinical.ClinicalNoteEmbeddings WHERE Embedding IS NOT NULL);

IF @rows >= 100
BEGIN
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'VIX_ClinicalNoteEmbeddings_Embedding')
        DROP INDEX VIX_ClinicalNoteEmbeddings_Embedding ON clinical.ClinicalNoteEmbeddings;

    CREATE VECTOR INDEX VIX_ClinicalNoteEmbeddings_Embedding
    ON clinical.ClinicalNoteEmbeddings (Embedding)
    WITH (METRIC = 'cosine', TYPE = 'diskann');

    PRINT '  DiskANN vector index created over ' + CAST(@rows AS VARCHAR(20)) + ' vectors.';
END
ELSE
    PRINT '  Only ' + CAST(@rows AS VARCHAR(20)) + ' embedded notes (< 100) — skipping index; exact scan will be used.';
GO

/* Proof it landed. */
SELECT i.name AS index_name, i.type_desc
FROM sys.indexes AS i
WHERE i.name = 'VIX_ClinicalNoteEmbeddings_Embedding';
GO

PRINT '07-vector-index.sql complete. Next: 08-ai-assistance.sql';
GO
