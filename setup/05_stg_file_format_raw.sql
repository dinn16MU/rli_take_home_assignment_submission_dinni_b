-- =====================================================================
-- 05: Stage, file formats and RAW tables
--
-- Design:
-- * RAW keeps every source column as VARCHAR (JSON as VARIANT), so a bad
--   value can never fail a load. Typing and cleanup happen in staging.
-- * Every table carries lineage columns: source file, source row, load time.
-- * Same objects in PROD_RAW and DEV_RAW so the load can be tested in dev
--   first. The DEV block is identical apart from its USE SCHEMA line.
-- * CREATE ... IF NOT EXISTS everywhere: safe to re-run, never drops data.
-- =====================================================================

USE ROLE SYSADMIN;


-- =====================================================================
-- PROD_RAW.INSURANCE
-- =====================================================================
USE SCHEMA PROD_RAW.INSURANCE;

-- ---------- File formats ----------
CREATE FILE FORMAT IF NOT EXISTS FF_CSV
  TYPE                           = CSV
  FIELD_DELIMITER                = ','
  SKIP_HEADER                    = 1
  FIELD_OPTIONALLY_ENCLOSED_BY   = '"'      -- names like "Ware, Cruz and Turner" contain commas
  NULL_IF                        = ('')     -- policy 6's missing premium lands as NULL
  EMPTY_FIELD_AS_NULL            = TRUE
  ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE     -- a malformed row fails loudly instead of shifting columns
  COMMENT = 'Source CSV extracts: header row, quoted fields, empty = NULL';

CREATE FILE FORMAT IF NOT EXISTS FF_JSON
  TYPE              = JSON
  STRIP_OUTER_ARRAY = TRUE                  -- file is one big array; each element becomes a row
  COMMENT = 'Source JSON extracts: top-level array of records';

-- ---------- Stage ----------
CREATE STAGE IF NOT EXISTS RAW_STAGE
  DIRECTORY = (ENABLE = TRUE)               -- lets you list uploaded files with SELECT * FROM DIRECTORY(@RAW_STAGE)
  COMMENT = 'Landing area for source files. Production equivalent: external stage fed by the source system';

-- ---------- RAW tables ----------
CREATE TABLE IF NOT EXISTS CUSTOMERS (
  CUSTOMER_ID       VARCHAR,
  CUSTOMER_NAME     VARCHAR,
  STATE             VARCHAR,
  INDUSTRY          VARCHAR,
  _FILE_NAME        VARCHAR,
  _FILE_ROW_NUMBER  NUMBER,
  _LOADED_AT        TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'Raw customers.csv, as landed (all VARCHAR)';

CREATE TABLE IF NOT EXISTS POLICIES (
  POLICY_ID         VARCHAR,
  CUSTOMER_ID       VARCHAR,
  POLICY_TYPE       VARCHAR,
  EFFECTIVE_DATE    VARCHAR,
  EXPIRATION_DATE   VARCHAR,
  PREMIUM           VARCHAR,
  _FILE_NAME        VARCHAR,
  _FILE_ROW_NUMBER  NUMBER,
  _LOADED_AT        TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'Raw policies.csv, as landed (all VARCHAR)';

CREATE TABLE IF NOT EXISTS CLAIMS (
  CLAIM_ID          VARCHAR,
  POLICY_ID         VARCHAR,
  CLAIM_DATE        VARCHAR,
  CLAIM_AMOUNT      VARCHAR,
  CLAIM_STATUS      VARCHAR,
  _FILE_NAME        VARCHAR,
  _FILE_ROW_NUMBER  NUMBER,
  _LOADED_AT        TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'Raw claims.csv, as landed (all VARCHAR)';

CREATE TABLE IF NOT EXISTS PAYMENTS (
  PAYMENT_ID        VARCHAR,
  POLICY_ID         VARCHAR,
  PAYMENT_DATE      VARCHAR,
  PAYMENT_AMOUNT    VARCHAR,
  _FILE_NAME        VARCHAR,
  _FILE_ROW_NUMBER  NUMBER,
  _LOADED_AT        TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'Raw payments.csv (premium collected), as landed (all VARCHAR)';

CREATE TABLE IF NOT EXISTS ENDORSEMENTS (
  RAW_DATA          VARIANT,
  _FILE_NAME        VARCHAR,
  _FILE_ROW_NUMBER  NUMBER,
  _LOADED_AT        TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'Raw endorsements.json, one JSON record per row';


-- =====================================================================
-- DEV_RAW.INSURANCE  (identical objects)
-- =====================================================================
USE SCHEMA DEV_RAW.INSURANCE;

CREATE FILE FORMAT IF NOT EXISTS FF_CSV
  TYPE                           = CSV
  FIELD_DELIMITER                = ','
  SKIP_HEADER                    = 1
  FIELD_OPTIONALLY_ENCLOSED_BY   = '"'
  NULL_IF                        = ('')
  EMPTY_FIELD_AS_NULL            = TRUE
  ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE
  COMMENT = 'Source CSV extracts: header row, quoted fields, empty = NULL';

CREATE FILE FORMAT IF NOT EXISTS FF_JSON
  TYPE              = JSON
  STRIP_OUTER_ARRAY = TRUE
  COMMENT = 'Source JSON extracts: top-level array of records';

CREATE STAGE IF NOT EXISTS RAW_STAGE
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Dev landing area for source files';

CREATE TABLE IF NOT EXISTS CUSTOMERS (
  CUSTOMER_ID VARCHAR, CUSTOMER_NAME VARCHAR, STATE VARCHAR, INDUSTRY VARCHAR,
  _FILE_NAME VARCHAR, _FILE_ROW_NUMBER NUMBER, _LOADED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'Raw customers.csv, as landed (all VARCHAR)';

CREATE TABLE IF NOT EXISTS POLICIES (
  POLICY_ID VARCHAR, CUSTOMER_ID VARCHAR, POLICY_TYPE VARCHAR, EFFECTIVE_DATE VARCHAR,
  EXPIRATION_DATE VARCHAR, PREMIUM VARCHAR,
  _FILE_NAME VARCHAR, _FILE_ROW_NUMBER NUMBER, _LOADED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'Raw policies.csv, as landed (all VARCHAR)';

CREATE TABLE IF NOT EXISTS CLAIMS (
  CLAIM_ID VARCHAR, POLICY_ID VARCHAR, CLAIM_DATE VARCHAR, CLAIM_AMOUNT VARCHAR, CLAIM_STATUS VARCHAR,
  _FILE_NAME VARCHAR, _FILE_ROW_NUMBER NUMBER, _LOADED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'Raw claims.csv, as landed (all VARCHAR)';

CREATE TABLE IF NOT EXISTS PAYMENTS (
  PAYMENT_ID VARCHAR, POLICY_ID VARCHAR, PAYMENT_DATE VARCHAR, PAYMENT_AMOUNT VARCHAR,
  _FILE_NAME VARCHAR, _FILE_ROW_NUMBER NUMBER, _LOADED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'Raw payments.csv (premium collected), as landed (all VARCHAR)';

CREATE TABLE IF NOT EXISTS ENDORSEMENTS (
  RAW_DATA VARIANT,
  _FILE_NAME VARCHAR, _FILE_ROW_NUMBER NUMBER, _LOADED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'Raw endorsements.json, one JSON record per row';


-- =====================================================================
-- GRANTS (SECURITYADMIN)
-- =====================================================================
USE ROLE SECURITYADMIN;

-- ---------- PROD: SERVICE_ROLE loads ----------
GRANT USAGE ON FILE FORMAT PROD_RAW.INSURANCE.FF_CSV    TO ROLE SERVICE_ROLE;
GRANT USAGE ON FILE FORMAT PROD_RAW.INSURANCE.FF_JSON   TO ROLE SERVICE_ROLE;
GRANT READ, WRITE ON STAGE PROD_RAW.INSURANCE.RAW_STAGE TO ROLE SERVICE_ROLE;  -- WRITE = can upload files
GRANT SELECT, INSERT ON ALL TABLES    IN SCHEMA PROD_RAW.INSURANCE TO ROLE SERVICE_ROLE;
GRANT SELECT, INSERT ON FUTURE TABLES IN SCHEMA PROD_RAW.INSURANCE TO ROLE SERVICE_ROLE;
-- DEVELOPER's read-only SELECT on PROD_RAW tables already comes from file 04's future grant.

-- ---------- DEV: DEVELOPER loads and tests ----------
GRANT USAGE ON FILE FORMAT DEV_RAW.INSURANCE.FF_CSV     TO ROLE DEVELOPER;
GRANT USAGE ON FILE FORMAT DEV_RAW.INSURANCE.FF_JSON    TO ROLE DEVELOPER;
GRANT READ, WRITE ON STAGE DEV_RAW.INSURANCE.RAW_STAGE  TO ROLE DEVELOPER;
-- Table privileges in DEV_RAW already come from file 04 (ALL ON FUTURE TABLES).


-- =====================================================================
-- CHECKS
-- =====================================================================
USE ROLE SYSADMIN;
SHOW FILE FORMATS IN SCHEMA PROD_RAW.INSURANCE;               -- FF_CSV, FF_JSON
SHOW STAGES       IN SCHEMA PROD_RAW.INSURANCE;               -- RAW_STAGE
SHOW TABLES       IN SCHEMA PROD_RAW.INSURANCE;               -- 5 tables, 0 rows
DESCRIBE TABLE PROD_RAW.INSURANCE.CLAIMS;                     -- VARCHAR columns + 3 lineage columns
SHOW GRANTS ON STAGE PROD_RAW.INSURANCE.RAW_STAGE;            -- SERVICE_ROLE: READ, WRITE
SHOW GRANTS TO ROLE DEVELOPER;                                -- includes DEV stage + file formats

