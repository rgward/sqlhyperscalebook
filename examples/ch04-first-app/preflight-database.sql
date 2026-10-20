SET NOCOUNT ON;

SELECT
    HasSchema = CASE
        WHEN OBJECT_ID(N'clinical.Patient') IS NOT NULL
         AND OBJECT_ID(N'clinical.GetPatientChart') IS NOT NULL THEN 1
        ELSE 0
    END,
    PatientCount = CASE
        WHEN OBJECT_ID(N'clinical.Patient') IS NULL THEN -1
        ELSE (SELECT COUNT(*) FROM clinical.Patient)
    END,
    -- Chapter 8: the RowLevelSecurity flag needs this policy to actually filter.
    HasRlsPolicy = CASE
        WHEN EXISTS (SELECT 1
                     FROM sys.security_policies
                     WHERE name = N'EncounterAccessPolicy'
                       AND SCHEMA_NAME(schema_id) = N'security'
                       AND is_enabled = 1) THEN 1
        ELSE 0
    END;
GO
