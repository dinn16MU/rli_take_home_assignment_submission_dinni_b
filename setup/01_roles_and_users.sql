-- =====================================================================
-- 01: Roles, role hierarchy and users
-- Functional roles:
--   ANALYST      -> reads curated data (MARTS, DQ, semantic view)
--   DEVELOPER    -> full in dev, read-only in prod; inherits ANALYST
--   SERVICE_ROLE -> runs loads and dbt (owns prod ANALYTICS objects)
-- All custom roles roll up to SYSADMIN so admins can see and manage
-- every object they own (no orphaned objects).
-- =====================================================================

USE ROLE USERADMIN;

CREATE ROLE IF NOT EXISTS ANALYST      COMMENT = 'Product Analytics / business users: read curated data only';
CREATE ROLE IF NOT EXISTS DEVELOPER    COMMENT = 'Data engineers: full access in dev, read-only in prod';
CREATE ROLE IF NOT EXISTS SERVICE_ROLE COMMENT = 'Automated loads and dbt runs (scheduled in Snowflake)';


-- ---------- Role hierarchy ----------
USE ROLE SECURITYADMIN;

GRANT ROLE ANALYST      TO ROLE DEVELOPER;   -- engineers see what analysts see
GRANT ROLE DEVELOPER    TO ROLE SYSADMIN;
GRANT ROLE SERVICE_ROLE TO ROLE SYSADMIN;


-- ---------- Service user ----------
-- Scheduled dbt runs execute inside Snowflake as SERVICE_ROLE and don't need
-- this user's credentials. DBT_SVC exists for runs from outside Snowflake
-- (e.g. a CI pipeline), which would authenticate with a key pair.
USE ROLE USERADMIN;

CREATE USER IF NOT EXISTS DBT_SVC
  TYPE              = SERVICE              -- no password or MFA login possible
  DEFAULT_ROLE      = SERVICE_ROLE
  DEFAULT_WAREHOUSE = RLI_DEV_WH
  COMMENT           = 'Service user for dbt runs from outside Snowflake (CI). Key-pair auth only.';

-- Set when an external runner is configured (public key body, no BEGIN/END lines):
-- ALTER USER DBT_SVC SET RSA_PUBLIC_KEY = '<public key>';

USE ROLE SECURITYADMIN;
GRANT ROLE SERVICE_ROLE TO USER DBT_SVC;


-- ---------- Whoever runs this setup ----------
-- Grants the roles to the current user, so the script runs on any account
-- without editing. Quoted so any user-name case works.
SET setup_user = '"' || CURRENT_USER() || '"';
GRANT ROLE DEVELOPER TO USER IDENTIFIER($setup_user);
GRANT ROLE ANALYST   TO USER IDENTIFIER($setup_user);   -- lets you USE ROLE ANALYST to test masking


-- ---------- Checks ----------
SHOW ROLES LIKE '%';
SHOW GRANTS OF ROLE ANALYST;        -- DEVELOPER + the current user
SHOW GRANTS TO USER DBT_SVC;        -- SERVICE_ROLE
