-- =====================================================================
-- 08: Reporting layer - CoWork agent on the semantic view
-- Run AFTER the first prod pipeline run (07): the semantic view must exist.
--
-- Analysts ask questions in CoWork. The agent answers only from the governed
-- metrics in SV_POLICY_PERFORMANCE, and its queries run as the person asking,
-- so ANALYST still sees hashed customer names (masking policy).
-- =====================================================================


-- ---------- 1. Account settings (ACCOUNTADMIN) ----------
USE ROLE ACCOUNTADMIN;

-- Let Cortex use a model hosted in another US region if it isn't available
-- in this account's region. Data stays in the US.
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_US';

-- The CoWork object: the curated list of agents users see in CoWork (one per account)
CREATE SNOWFLAKE INTELLIGENCE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;


-- ---------- 2. The agent (SYSADMIN owns the SEMANTIC schema) ----------
USE ROLE SYSADMIN;

CREATE OR REPLACE AGENT PROD_ANALYTICS.SEMANTIC.POLICY_PERFORMANCE_AGENT
  COMMENT = 'Answers loss ratio, claims, premium and risk questions from SV_POLICY_PERFORMANCE'
  PROFILE = '{"display_name": "Policy Performance Analyst"}'
  FROM SPECIFICATION
$$
models:
  orchestration: auto

instructions:
  response: >
    Answer for business users. Show ratios as percentages with one decimal.
    Say which metric you used and include a short table when comparing groups.
    When ranking risk, mention premium size next to the loss ratio so small
    policies with one large claim are not over-weighted.
    Customer names are hashed for analysts; never try to reveal them.
  orchestration: >
    Use the policy_performance tool for every data question.
    Business definitions:
    - Loss ratio = claims / written premium. It excludes claims dated before
      the policy started, includes claims after the policy ended, and
      excludes policies with no premium from both sides.
    - Adjusted loss ratio uses premium after endorsements.
    - Payments are premium collected from customers, not claim payouts.
      Collection rate = premium collected / written premium.
    - Open claim exposure = amount on Open and Pending claims.
    - Elevated risk = high loss ratio and/or high open claim exposure,
      by customer, policy type, state or industry.
  sample_questions:
    - question: "Which policy types have the highest loss ratio?"
    - question: "How do claims and premium collected trend by month for each policy type?"
    - question: "Which customers have the highest loss ratio and open claim exposure?"
    - question: "Show written premium, claims and loss ratio by policy start month."

tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "policy_performance"
      description: >
        Insurance policy performance: written premium, claims, loss ratio,
        premium collected and open claim exposure by policy type, state,
        industry, customer and month.

tool_resources:
  policy_performance:
    semantic_view: "PROD_ANALYTICS.SEMANTIC.SV_POLICY_PERFORMANCE"
    execution_environment:
      type: "warehouse"
      warehouse: "RLI_ANALYST_WH"
$$;

-- Who can use the agent
GRANT USAGE ON AGENT PROD_ANALYTICS.SEMANTIC.POLICY_PERFORMANCE_AGENT TO ROLE ANALYST;
GRANT USAGE ON AGENT PROD_ANALYTICS.SEMANTIC.POLICY_PERFORMANCE_AGENT TO ROLE DEVELOPER;


-- ---------- 3. Publish in CoWork (ACCOUNTADMIN) ----------
USE ROLE ACCOUNTADMIN;

ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT
  ADD AGENT PROD_ANALYTICS.SEMANTIC.POLICY_PERFORMANCE_AGENT;

GRANT USAGE ON SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT TO ROLE ANALYST;
GRANT USAGE ON SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT TO ROLE DEVELOPER;

-- Cortex Agents / CoWork only (narrower than CORTEX_USER, which PUBLIC has by default)
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE ANALYST;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE DEVELOPER;


-- ---------- Checks ----------
SHOW AGENTS IN SCHEMA PROD_ANALYTICS.SEMANTIC;
SHOW SNOWFLAKE INTELLIGENCES;
