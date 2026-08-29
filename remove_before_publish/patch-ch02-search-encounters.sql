/* ============================================================================
   TEMPORARY TECH-REVIEW PATCH — remove before publication

   Applies the revised Chapter 2 clinical.SearchEncounters contract to a
   wardgeneral database that was deployed before the Chapter 6 review.

   The change is backward compatible: the original six ID/date parameters and
   result columns remain. The procedure adds optional human-readable filters,
   a row cap, and readable names used by the Chapter 6 DAB/MCP tool.

   Rerunnable. Creates no new object and changes no data.
   All data is synthetic — no real PHI.
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

CREATE OR ALTER PROCEDURE clinical.SearchEncounters
    @PatientId           INT           = NULL,
    @DepartmentId        INT           = NULL,
    @AttendingProviderId INT           = NULL,
    @Status              NVARCHAR(20)  = NULL,
    @FromAdmit           DATETIME2(3)  = NULL,
    @ToAdmit             DATETIME2(3)  = NULL,
    @UnitName            NVARCHAR(100) = NULL,
    @DepartmentName      NVARCHAR(100) = NULL,
    @ProviderName        NVARCHAR(200) = NULL,
    @Top                 INT           = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @Status         = NULLIF(LTRIM(RTRIM(@Status)), N'');
    SET @UnitName       = NULLIF(LTRIM(RTRIM(@UnitName)), N'');
    SET @DepartmentName = NULLIF(LTRIM(RTRIM(@DepartmentName)), N'');
    SET @ProviderName   = NULLIF(LTRIM(RTRIM(@ProviderName)), N'');
    IF @Top IS NOT NULL AND @Top < 1 SET @Top = 200;

    SELECT TOP (CASE WHEN @Top IS NULL THEN 2147483647 ELSE @Top END)
        e.EncounterId,
        e.PatientId,
        p.FullName AS PatientName,
        e.DepartmentId,
        d.Name AS DepartmentName,
        e.AttendingProviderId,
        pr.FullName AS AttendingProviderName,
        e.BedId,
        u.Name AS UnitName,
        b.BedNumber,
        e.EncounterType,
        e.AdmitTime,
        e.DischargeTime,
        e.Status
    FROM clinical.Encounter AS e
        JOIN clinical.Patient AS p
            ON p.PatientId = e.PatientId
        JOIN ops.Department AS d
            ON d.DepartmentId = e.DepartmentId
        JOIN ops.Provider AS pr
            ON pr.ProviderId = e.AttendingProviderId
        LEFT JOIN ops.Bed AS b
            ON b.BedId = e.BedId
        LEFT JOIN ops.Unit AS u
            ON u.UnitId = b.UnitId
    WHERE (@PatientId           IS NULL OR e.PatientId           = @PatientId)
      AND (@DepartmentId        IS NULL OR e.DepartmentId        = @DepartmentId)
      AND (@AttendingProviderId IS NULL OR e.AttendingProviderId = @AttendingProviderId)
      AND (@Status              IS NULL OR e.Status              = @Status)
      AND (@FromAdmit           IS NULL OR e.AdmitTime          >= @FromAdmit)
      AND (@ToAdmit             IS NULL OR e.AdmitTime          <= @ToAdmit)
      AND (@UnitName            IS NULL OR u.Name                 = @UnitName)
      AND (@DepartmentName      IS NULL OR d.Name                 = @DepartmentName)
      AND (@ProviderName        IS NULL OR pr.FullName LIKE N'%' + @ProviderName + N'%')
    ORDER BY e.AdmitTime DESC;
END;
GO

/* Verification: expect ten rows, ending with @Top. */
SELECT
    p.parameter_id,
    p.name AS ParameterName,
    TYPE_NAME(p.user_type_id) AS TypeName,
    p.max_length AS MaxLength
FROM sys.parameters AS p
WHERE p.object_id = OBJECT_ID(N'clinical.SearchEncounters')
ORDER BY p.parameter_id;
GO

PRINT 'Chapter 2 patch complete — clinical.SearchEncounters now supports ID, date, name, status, and row-cap filters.';
GO
