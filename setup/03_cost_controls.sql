-- =====================================================================
-- 03: Cost controls (resource monitors)
-- Account administrators with email notifications enabled receive the
-- alerts automatically.
-- =====================================================================

USE ROLE ACCOUNTADMIN;

-- Account-wide monthly cap
CREATE RESOURCE MONITOR IF NOT EXISTS RM_ACCOUNT_MONTHLY WITH
  CREDIT_QUOTA    = 50
  FREQUENCY       = MONTHLY
  START_TIMESTAMP = IMMEDIATELY
  TRIGGERS
    ON 75 PERCENT  DO NOTIFY
    ON 100 PERCENT DO SUSPEND
    ON 110 PERCENT DO SUSPEND_IMMEDIATE;

ALTER ACCOUNT SET RESOURCE_MONITOR = RM_ACCOUNT_MONTHLY;

-- Smaller cap on the analyst warehouse (ad-hoc and AI-generated queries)
CREATE RESOURCE MONITOR IF NOT EXISTS RM_ANALYTICS_WH WITH
  CREDIT_QUOTA    = 20
  FREQUENCY       = MONTHLY
  START_TIMESTAMP = IMMEDIATELY
  TRIGGERS
    ON 75 PERCENT  DO NOTIFY
    ON 100 PERCENT DO SUSPEND
    ON 110 PERCENT DO SUSPEND_IMMEDIATE;

ALTER WAREHOUSE RLI_ANALYST_WH SET RESOURCE_MONITOR = RM_ANALYTICS_WH;

-- Optional manual step (UI only): activate the account Budget in Snowsight
-- (Admin -> Cost Management -> Budgets) with a monthly limit and email alert.
-- Resource monitors only track warehouse credits; the Budget also covers
-- serverless and AI features such as Cortex (CoWork).


-- ---------- Checks ----------
SHOW RESOURCE MONITORS;
