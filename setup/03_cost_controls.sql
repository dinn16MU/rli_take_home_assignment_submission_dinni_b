USE ROLE ACCOUNTADMIN;

--Resource Monitor for account 
-- Alerts: account administrators with email notifications enabled receive
-- resource monitor alerts automatically. Add NOTIFY_USERS = (<user>) to also
-- alert specific non-admin users.

CREATE RESOURCE MONITOR IF NOT EXISTS RM_ACCOUNT_MONTHLY WITH
CREDIT_QUOTA = 50
FREQUENCY = MONTHLY
START_TIMESTAMP = IMMEDIATELY
-- NOTIFY_USERS = ("")
TRIGGERS
ON 75 PERCENT DO NOTIFY
ON 100 PERCENT DO SUSPEND
ON 110 PERCENT DO SUSPEND_IMMEDIATE;

ALTER ACCOUNT SET RESOURCE_MONITOR = RM_ACCOUNT_MONTHLY;


--Smaller monitor for analytics warehouse
CREATE RESOURCE MONITOR IF NOT EXISTS RM_ANALYTICS_WH WITH
CREDIT_QUOTA = 20
FREQUENCY = MONTHLY
START_TIMESTAMP = IMMEDIATELY
--NOTIFY_USERS = ("")
TRIGGERS
ON 75 PERCENT DO NOTIFY
ON 100 PERCENT DO SUSPEND
ON 110 PERCENT DO SUSPEND_IMMEDIATE;

ALTER WAREHOUSE RLI_ANALYST_WH SET RESOURCE_MONITOR = RM_ANALYTICS_WH;


SHOW RESOURCE MONITORS;

-- Optional manual step (UI only): activate the account Budget in Snowsight
-- (Admin -> Cost Management -> Budgets) with a monthly limit and email alert.
-- Resource monitors only track warehouse credits; the Budget also covers
-- serverless and AI features such as Cortex.
