-- =====================================================================
-- Runs every setup script in order, straight from the Git repository.
-- Called by 00_bootstrap_git.sql. Each script sets its own role.
-- All scripts are safe to re-run (IF NOT EXISTS everywhere).
-- =====================================================================

EXECUTE IMMEDIATE FROM @RLI_PLATFORM.INTEGRATIONS.RLI_TAKEHOME_REPO/branches/main/setup/01_roles_and_users.sql;
EXECUTE IMMEDIATE FROM @RLI_PLATFORM.INTEGRATIONS.RLI_TAKEHOME_REPO/branches/main/setup/02_warehouses.sql;
EXECUTE IMMEDIATE FROM @RLI_PLATFORM.INTEGRATIONS.RLI_TAKEHOME_REPO/branches/main/setup/03_cost_controls.sql;
EXECUTE IMMEDIATE FROM @RLI_PLATFORM.INTEGRATIONS.RLI_TAKEHOME_REPO/branches/main/setup/04_db_and_schema_grants.sql;
EXECUTE IMMEDIATE FROM @RLI_PLATFORM.INTEGRATIONS.RLI_TAKEHOME_REPO/branches/main/setup/05_stg_file_format_raw.sql;
EXECUTE IMMEDIATE FROM @RLI_PLATFORM.INTEGRATIONS.RLI_TAKEHOME_REPO/branches/main/setup/06_masking_policy.sql;
-- 07 (dbt project + tasks) is added in step 4
