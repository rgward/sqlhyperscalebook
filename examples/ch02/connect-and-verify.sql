/* ============================================================================
   Inside Azure SQL Hyperscale — Chapter 2
   connect-and-verify.sql : prove it's SQL Server, and prove it's Hyperscale.
   Run order              : after `provision-hyperscale.azcli` succeeds.
                            (Independent of 01-schemas..05-seed; safe to re-run.)

   This is the captured "prove it's SQL Server" moment that Ch 1 §6 forward-points
   to. Output should show ServiceObjective starting with HS_ and Edition = Hyperscale.
   ============================================================================ */

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET NUMERIC_ROUNDABORT OFF;
GO

PRINT N'-- @@VERSION ---------------------------------------------------------';
SELECT @@VERSION AS Version;
GO

PRINT N'-- Database identity and service tier --------------------------------';
SELECT
    DB_NAME()                                                              AS DatabaseName,
    @@SERVERNAME                                                           AS LogicalServer,
    CAST(DATABASEPROPERTYEX(DB_NAME(), 'Edition')           AS NVARCHAR(50)) AS Edition,
    CAST(DATABASEPROPERTYEX(DB_NAME(), 'ServiceObjective')  AS NVARCHAR(50)) AS ServiceObjective,
    CAST(DATABASEPROPERTYEX(DB_NAME(), 'Updateability')     AS NVARCHAR(50)) AS Updateability,
    CAST(DATABASEPROPERTYEX(DB_NAME(), 'IsXTPSupported')    AS BIT)          AS IsXTPSupported;
/* Expected on the wardgeneral primary:
     Edition          = Hyperscale
     ServiceObjective = HS_<series>_<vCores>     (e.g. HS_Gen5_8 or HS_PRMS_8)
     Updateability    = READ_WRITE
*/
GO

PRINT N'-- Resource limits in effect for this database ----------------------';
SELECT
    slo_name,
    cpu_limit,
    instance_max_worker_threads,
    primary_max_log_rate,
    primary_group_max_io,
    max_db_max_size_in_mb
FROM sys.dm_user_db_resource_governance
WHERE database_id = DB_ID();
GO

PRINT N'-- Replica role (primary vs HA-replica vs named replica) ------------';
SELECT
    DATABASEPROPERTYEX(DB_NAME(), 'Updateability') AS Updateability,
    -- HA replicas report 'READ_ONLY'; the primary reports 'READ_WRITE'.
    -- Named replicas are always READ_ONLY too but are surfaced as separate databases.
    HOST_NAME()         AS GatewayHost,
    CONNECTIONPROPERTY('client_net_address') AS ClientNetAddress,
    CONNECTIONPROPERTY('local_net_address')  AS LocalNetAddress;
GO

PRINT N'-- Schema sanity (after 01-schemas.sql + 02-tables.sql have run) ----';
SELECT TABLE_SCHEMA, TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA IN (N'clinical', N'ops')
  AND TABLE_TYPE = N'BASE TABLE'
ORDER BY TABLE_SCHEMA, TABLE_NAME;
/* Expected: 13 base tables across the clinical.* and ops.* schemas.
   (The clinical.v* and ops.v* views from 03-views.sql are excluded here.) */
GO
