-- =====================================================================
-- 02: Warehouses (one per workload)
-- Separate warehouses keep loads, transforms and reporting from competing
-- for compute, and make cost attributable per workload.
-- All: auto-resume on demand, start suspended, statement timeouts to stop
-- runaway queries.
-- =====================================================================

USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS RLI_LOAD_WH
  WAREHOUSE_SIZE               = 'XSMALL'
  AUTO_SUSPEND                 = 60          -- short bursty COPY jobs
  AUTO_RESUME                  = TRUE
  INITIALLY_SUSPENDED          = TRUE
  STATEMENT_TIMEOUT_IN_SECONDS = 600
  COMMENT = 'COPY INTO loads from stage into RAW. Short bursts, suspends fast.';

CREATE WAREHOUSE IF NOT EXISTS RLI_DEV_WH
  WAREHOUSE_SIZE               = 'XSMALL'    -- raise to SMALL if dbt runs get slow
  AUTO_SUSPEND                 = 60          -- batch work, no value staying warm
  AUTO_RESUME                  = TRUE
  INITIALLY_SUSPENDED          = TRUE
  STATEMENT_TIMEOUT_IN_SECONDS = 1800
  COMMENT = 'dbt builds (dev and scheduled prod runs). Batch work, suspends fast.';

CREATE WAREHOUSE IF NOT EXISTS RLI_ANALYST_WH
  WAREHOUSE_SIZE               = 'XSMALL'
  AUTO_SUSPEND                 = 300         -- stays warm 5 min so repeat report queries reuse cache
  AUTO_RESUME                  = TRUE
  INITIALLY_SUSPENDED          = TRUE
  STATEMENT_TIMEOUT_IN_SECONDS = 300         -- caps runaway report / AI-generated queries
  MIN_CLUSTER_COUNT            = 1
  MAX_CLUSTER_COUNT            = 2           -- scales out for concurrent users, not up
  SCALING_POLICY               = 'STANDARD'
  COMMENT = 'Analysts and Streamlit reporting. Stays warm 5 min to reuse cache; scales out for concurrency.';


-- ---------- Grants ----------
USE ROLE SECURITYADMIN;

-- SERVICE_ROLE: loads and scheduled dbt runs
GRANT USAGE ON WAREHOUSE RLI_LOAD_WH      TO ROLE SERVICE_ROLE;
GRANT USAGE ON WAREHOUSE RLI_DEV_WH TO ROLE SERVICE_ROLE;

-- DEVELOPER: everything, so dev mirrors prod (incl. testing loads)
GRANT USAGE, MONITOR ON WAREHOUSE RLI_LOAD_WH      TO ROLE DEVELOPER;
GRANT USAGE, MONITOR ON WAREHOUSE RLI_DEV_WH TO ROLE DEVELOPER;
GRANT USAGE, MONITOR ON WAREHOUSE RLI_ANALYST_WH   TO ROLE DEVELOPER;

-- ANALYST: reporting only
GRANT USAGE ON WAREHOUSE RLI_ANALYST_WH TO ROLE ANALYST;


-- ---------- Checks ----------
SHOW WAREHOUSES LIKE 'RLI%';
SHOW GRANTS ON WAREHOUSE RLI_DEV_WH;
