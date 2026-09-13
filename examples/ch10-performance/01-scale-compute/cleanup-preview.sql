/* Preview exact Demo 1 rows. This script changes nothing. */

SET NOCOUNT ON;

SELECT Marker = N'CH10-SCALE', TableName, RowsToDelete
FROM
(
    SELECT N'clinical.Observation', COUNT_BIG(*)
    FROM clinical.Observation
    WHERE Unit LIKE N'CH10-SCALE:%'

    UNION ALL

    SELECT N'clinical.MedicationOrder', COUNT_BIG(*)
    FROM clinical.MedicationOrder
    WHERE MedicationName = N'CH10-SCALE:Acetaminophen'

    UNION ALL

    SELECT N'clinical.LabResult', COUNT_BIG(*)
    FROM clinical.LabResult
    WHERE JSON_VALUE(ResultJson, '$.source') = N'CH10-SCALE'

    UNION ALL

    SELECT N'clinical.ClinicalNote', COUNT_BIG(*)
    FROM clinical.ClinicalNote
    WHERE NoteText LIKE N'CH10-SCALE:%'
) AS counts(TableName, RowsToDelete)
ORDER BY TableName;

IF OBJECT_ID(N'clinical.ClinicalNoteEmbeddings', N'U') IS NOT NULL
BEGIN
    DECLARE @EmbeddingCount BIGINT;

    EXEC sys.sp_executesql
        N'SELECT @Count = COUNT_BIG(*)
          FROM clinical.ClinicalNoteEmbeddings AS e
          JOIN clinical.ClinicalNote AS n ON n.NoteId = e.NoteId
          WHERE n.NoteText LIKE N''CH10-SCALE:%'';',
        N'@Count BIGINT OUTPUT',
        @Count = @EmbeddingCount OUTPUT;

    SELECT
        Marker = N'CH10-SCALE',
        TableName = N'clinical.ClinicalNoteEmbeddings',
        RowsToDelete = @EmbeddingCount;
END;
