/* ============================================================================
   Azure SQL Hyperscale Unveiled — Chapter 2
   connect-and-verify.sql : prove it's SQL Server, and prove it's Hyperscale.
   Run order              : after `provision-hyperscale.ps1` succeeds.
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
    slo_name,                     -- INTERNAL governance name (reflects the physical
                                  -- hardware mapping, e.g. Gen5-on-Gen8). Your SKU is
                                  -- the ServiceObjective above (HS_Gen5_8). Don't parse this.
    cpu_limit,                    -- vCores (8 for HS_Gen5_8)
    primary_pool_max_workers,     -- worker limit for the user resource POOL (=840 on HS_Gen5_8).
                                  -- Sits just above the published workload-GROUP limit of ~800 --
                                  -- the "~100 concurrent workers/vCore" the docs cite and error 10928
                                  -- enforces (see sys.dm_resource_governor_workload_groups_history_ex.max_worker).
                                  -- (instance_max_worker_threads, ~1640, is the whole node's SQLOS pool --
                                  -- deliberately not shown; not your limit.) Read live usage as a %
                                  -- via sys.dm_db_resource_stats.max_worker_percent.
    max_sessions,                 -- session limit for the user group (30,000 flat on Hyperscale)
    primary_max_log_rate,         -- bytes/sec; / 1048576 = MiB/s (the WRITE ceiling,
                                  -- ~105 MiB/s on HS_Gen5_8 -- the Ch 10 log-rate governor)
    primary_group_max_io,         -- max IOPS for the primary user workload group
    max_db_max_size_in_mb         -- MB; / 1024 / 1024 = 128 TB Hyperscale ceiling
                                  -- (you still pay only for ACTUAL allocation)
FROM sys.dm_user_db_resource_governance
WHERE database_id = DB_ID();
GO

PRINT N'-- Replica role (primary vs HA / geo / named replica) ---------------';
SELECT
    rg.replica_role,   -- 0 = primary, 1 = HA secondary, 2 = geo forwarder, 3 = named replica
    CASE rg.replica_role
        WHEN 0 THEN N'primary (read-write)'
        WHEN 1 THEN N'HA secondary (read-only)'
        WHEN 2 THEN N'geo forwarder'
        WHEN 3 THEN N'named replica (read-only)'
    END                                                     AS ReplicaRoleDesc,
    CAST(DATABASEPROPERTYEX(DB_NAME(),'Updateability') AS NVARCHAR(20)) AS Updateability, -- READ_WRITE on the primary
    CONNECTIONPROPERTY('client_net_address')                AS ClientIpAsSeenByServer     -- your machine's (NAT) IP
    -- NOTE: HOST_NAME() would return the CLIENT machine name (not a gateway), and
    -- CONNECTIONPROPERTY('local_net_address') is NULL on Azure SQL Database because
    -- connections terminate at the Azure SQL GATEWAY, not directly on the node NIC.
FROM sys.dm_user_db_resource_governance rg
WHERE rg.database_id = DB_ID();
GO

/* Schema verification (the 13 clinical and ops base tables) is intentionally
   NOT here — this script proves the tier only. Table/row verification lives in
   verify-data.sql, run after 01-schemas.sql .. 05-seed.sql. */
