-- =====================================================================
-- 00: Bootstrap. The ONLY script you paste into Snowsight.
-- Connects Snowflake to the public GitHub repo, then runs every setup
-- script directly from the repo. Run as a user with ACCOUNTADMIN.
-- =====================================================================

-- ---------- 1. Allow Snowflake to read from GitHub (public repo, no credentials) ----------
USE ROLE ACCOUNTADMIN;

CREATE API INTEGRATION IF NOT EXISTS RLI_GITHUB_API
  API_PROVIDER         = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/<github-account>')
  ENABLED              = TRUE
  COMMENT              = 'Read-only access to the public take-home repo';

GRANT USAGE ON INTEGRATION RLI_GITHUB_API TO ROLE SYSADMIN;


-- ---------- 2. Home for pipeline plumbing (Git repo, dbt project, tasks) ----------
USE ROLE SYSADMIN;

CREATE DATABASE IF NOT EXISTS RLI_PLATFORM
  COMMENT = 'Pipeline plumbing: Git repository, dbt project object, scheduled tasks';
CREATE SCHEMA IF NOT EXISTS RLI_PLATFORM.INTEGRATIONS;

CREATE GIT REPOSITORY IF NOT EXISTS RLI_PLATFORM.INTEGRATIONS.RLI_TAKEHOME_REPO
  API_INTEGRATION = RLI_GITHUB_API
  ORIGIN          = 'https://github.com/<github-account>/<repo-name>.git'
  COMMENT         = 'Clone of the take-home repo: setup scripts, data files, dbt project';

-- Pull the latest commit (safe to re-run any time)
ALTER GIT REPOSITORY RLI_PLATFORM.INTEGRATIONS.RLI_TAKEHOME_REPO FETCH;

-- Check: should list setup/, data/, dbt/ ...
LS @RLI_PLATFORM.INTEGRATIONS.RLI_TAKEHOME_REPO/branches/main;


-- ---------- 3. Run all setup scripts from the repo ----------
USE ROLE ACCOUNTADMIN;
EXECUTE IMMEDIATE FROM @RLI_PLATFORM.INTEGRATIONS.RLI_TAKEHOME_REPO/branches/main/setup/run_all.sql;
