-- =====================================================================
-- 06: Masking policy for customer_name
-- DEVELOPER and SERVICE_ROLE see the real value; everyone else (ANALYST,
-- and therefore CoWork answers) sees a consistent hash.
-- =====================================================================

USE ROLE SYSADMIN;

-- PROD
CREATE MASKING POLICY IF NOT EXISTS PROD_ANALYTICS.GOVERNANCE.MP_CUSTOMER_NAME
  AS (val STRING) RETURNS STRING ->
  CASE
    WHEN IS_ROLE_IN_SESSION('DEVELOPER')
      OR IS_ROLE_IN_SESSION('SERVICE_ROLE') THEN val
    WHEN val IS NULL THEN NULL
    ELSE 'CUST_' || LEFT(SHA2(val, 256), 12)
  END
  COMMENT = 'Hashes customer_name for non-privileged roles. Hash is deterministic so grouping and counting still work.';

-- DEV
CREATE MASKING POLICY IF NOT EXISTS DEV_ANALYTICS.GOVERNANCE.MP_CUSTOMER_NAME
  AS (val STRING) RETURNS STRING ->
  CASE
    WHEN IS_ROLE_IN_SESSION('DEVELOPER')
      OR IS_ROLE_IN_SESSION('SERVICE_ROLE') THEN val
    WHEN val IS NULL THEN NULL
    ELSE 'CUST_' || LEFT(SHA2(val, 256), 12)
  END
  COMMENT = 'Hashes customer_name for non-privileged roles. Hash is deterministic so grouping and counting still work.';


USE ROLE SECURITYADMIN;

-- APPLY lets the role attach the policy to columns of tables it owns
GRANT APPLY ON MASKING POLICY PROD_ANALYTICS.GOVERNANCE.MP_CUSTOMER_NAME TO ROLE SERVICE_ROLE;
GRANT APPLY ON MASKING POLICY DEV_ANALYTICS.GOVERNANCE.MP_CUSTOMER_NAME  TO ROLE DEVELOPER;


-- CHECKS
SHOW MASKING POLICIES IN SCHEMA PROD_ANALYTICS.GOVERNANCE;
SHOW GRANTS ON MASKING POLICY PROD_ANALYTICS.GOVERNANCE.MP_CUSTOMER_NAME;
SHOW GRANTS ON MASKING POLICY DEV_ANALYTICS.GOVERNANCE.MP_CUSTOMER_NAME;
