-- =====================================================================
-- 07: Schedule the pipeline with Snowflake Tasks
-- Run AFTER deploying the dbt project from the workspace as
-- PROD_ANALYTICS.ORCHESTRATION.INSURANCE_ANALYTICS (role SYSADMIN).
--
-- Task graph, daily at 6:00 AM Central:
--   T_LOAD_RAW      dbt run-operation load_raw   stage files -> PROD_RAW
--     -> T_DBT_BUILD  dbt build                  staging, dq, marts, semantic view + tests
-- =====================================================================


-- ---------- 1. Let the service role run the deployed project ----------
-- SYSADMIN deploys (owns) the project; SERVICE_ROLE only executes it.
USE ROLE SYSADMIN;
GRANT USAGE ON DBT PROJECT PROD_ANALYTICS.ORCHESTRATION.INSURANCE_ANALYTICS TO ROLE SERVICE_ROLE;


-- ---------- 2. Tasks, owned by the service role (not a person) ----------
USE ROLE SERVICE_ROLE;

CREATE OR REPLACE TASK PROD_ANALYTICS.ORCHESTRATION.T_LOAD_RAW
  WAREHOUSE = RLI_LOAD_WH
  SCHEDULE  = 'USING CRON 0 6 * * * America/Chicago'
  COMMENT   = 'Daily: load staged source files into PROD_RAW (files already loaded are skipped)'
AS
  EXECUTE DBT PROJECT PROD_ANALYTICS.ORCHESTRATION.INSURANCE_ANALYTICS
    ARGS = 'run-operation load_raw --target prod';

CREATE OR REPLACE TASK PROD_ANALYTICS.ORCHESTRATION.T_DBT_BUILD
  WAREHOUSE = RLI_DEV_WH
  COMMENT   = 'After T_LOAD_RAW: build and test every model in PROD_ANALYTICS'
  AFTER PROD_ANALYTICS.ORCHESTRATION.T_LOAD_RAW
AS
  EXECUTE DBT PROJECT PROD_ANALYTICS.ORCHESTRATION.INSURANCE_ANALYTICS
    ARGS = 'build --target prod';

-- New tasks start suspended. Resume the child first, then the root.
ALTER TASK PROD_ANALYTICS.ORCHESTRATION.T_DBT_BUILD RESUME;
ALTER TASK PROD_ANALYTICS.ORCHESTRATION.T_LOAD_RAW  RESUME;


-- ---------- 3. Run once now instead of waiting for 6 AM ----------
EXECUTE TASK PROD_ANALYTICS.ORCHESTRATION.T_LOAD_RAW;


-- ---------- Checks ----------
SHOW TASKS IN SCHEMA PROD_ANALYTICS.ORCHESTRATION;

-- Run history (re-run after a minute or two; both tasks should show SUCCEEDED)
SELECT name, state, scheduled_time, completed_time, error_message
FROM TABLE(PROD_ANALYTICS.INFORMATION_SCHEMA.TASK_HISTORY(RESULT_LIMIT => 10))
ORDER BY scheduled_time DESC;

-- To stop the daily schedule:
-- ALTER TASK PROD_ANALYTICS.ORCHESTRATION.T_LOAD_RAW SUSPEND;
