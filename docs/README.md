# Plan: Insurance Policy Performance — Curated Analytics Layer on Snowflake

## 1. Context — the ask and the constraints

**What the Product Analytics team needs:** a curated, trustworthy reporting layer that answers:
1. Which policy types have the highest loss ratios?
2. How do claims and payments trend across policy segments?
3. Which customers or policy groups carry elevated financial risk?
4. How can leadership track profitability and claims exposure over time?

**Hard constraints from the README**
- Must be built **in Snowflake** (a trial account is fine).
- Raw data contains **intentional DQ issues**: duplicates, orphan FKs, missing values, negative amounts, invalid dates.
- Must also show **production operations**: RBAC (engineer / analyst / service), warehouse configuration (auto-suspend/resume), cost control (resource monitor), grants, one sensitive-data protection example, and how to monitor, troubleshoot and deploy across environments.

**Soft constraints:** perfection isn't expected; reviewers grade **judgment, tradeoffs and communication**. So: small, clean, explainable, and designed to scale. It doesn't need to be enterprise-complete.

**Key definitions**
- Tooling: dbt, developed locally with dbt Core and **deployed and scheduled inside Snowflake** (dbt Projects on Snowflake + a Snowflake Task). Code is pushed to GitHub once the pipeline is built.
- Consumption through a **Snowflake semantic view**. Reporting front end: **Streamlit in Snowflake** (tentative). Because metrics live in the semantic view, the front end can change (Streamlit, CoWork, a BI tool) without changing the model.
- `payments.csv` = **premium collected** from customers against their policies.
- Loss ratio = **claims / premium**, as defined in the assignment. Its limitations are documented in §4.
- Endorsement sign and out-of-term claims are judgment calls; the decisions and reasoning are in §4.

---

## 2. The data and its relationships

```
customers (352) 1───* policies (1,004) 1───* claims (425)
                                       1───* payments (3,554)
                                       1───* endorsements (50, JSON)
```

| Entity | Grain / PK | Key columns | Notes |
|---|---|---|---|
| customers | customer_id | customer_name, state (8), industry (5) | `customer_name` is the only identifying field, so it gets the masking example |
| policies | policy_id | customer_id, policy_type (5), effective/expiration_date, premium | Central entity; everything else hangs off it |
| claims | claim_id | policy_id, claim_date, claim_amount, claim_status (Open/Pending/Closed) | 345 of 1,004 policies have claims |
| payments | payment_id | policy_id, payment_date, payment_amount | **Premium collected** from customers; links to the policy, not a claim |
| endorsements | endorsement_id | policy_id, type (Increase/Reduction/Cancellation), date, amount | JSON array; premium adjustments (change in premium) |

**Profiled data quality findings (actual counts).** The discovery file in step 3 reproduces these in Snowflake SQL.

| Issue | Where | Detail | Handling |
|---|---|---|---|
| Duplicate PK + orphan FK | claims | `claim_id=1` appears twice; the 2nd copy points to `policy_id=999999` (doesn't exist) | Dedupe on PK, prefer the row with a valid FK; send the loser to quarantine |
| Missing value | policies | `policy_id=6` has a null premium | Keep the policy and flag it; exclude it from loss-ratio denominators (**don't** impute 0) |
| Invalid date relationship | policies | `policy_id=21` expires before it starts | Keep and flag `is_invalid_term` |
| Negative amount | payments | `payment_id=11` = -500.00 | Keep and flag as a likely reversal/refund |
| Sign vs type mismatch | endorsements | Signs split ~50/50 within every type (Increase 9+/7−, Reduction 10+/12−, Cancellation 8+/4−), so no single sign convention fits | Trust the **type**; derive the sign from it (see §4); keep the raw amount and flag `is_sign_mismatch` |
| Claim before policy start | claims | 60 claims dated before the effective date | Keep and flag; **exclude from the loss ratio** (no coverage existed) |
| Claim after policy end | claims | 118 claims dated after the expiration date | Keep and flag; **include** in the loss ratio (late reporting is normal) |
| Payment outside term | payments | 458 before start, 1,126 after end | Keep and flag; advance payments and late installments are plausible |
| Endorsement after policy end | endorsements | 30 dated after expiration | Keep and flag; exclude from adjusted premium (an expired policy can't be changed) |
| Collections exceed premium | payments vs policies | 643 of 1,002 policies collected more than their premium (median 1.43×); policy length doesn't explain it | Report as-is with an `is_over_collected` flag; documented limitation, not "fixed" |

All ID, date and number formats parse cleanly (ISO dates, numeric amounts).

---

## 3. Architecture

```
CSV / JSON ──upload──► internal stage ──dbt run-operation (COPY INTO)──► RAW ──► discovery SQL (profiling)
                                                                           │
                                                                          dbt
                                                                           ▼
                                   STAGING (typed, cleaned, flagged) ──► MARTS (star schema)
                                          └──► DQ (quarantine + summary)        │
                                                                                ▼
                                                    SEMANTIC VIEW (metrics, dimensions, relationships, synonyms)
                                                                                │
                                                                                ▼
                                                    Cortex Agent (Cortex Analyst tool) ──► Snowflake CoWork (business users)
```

**Snowflake layout (one database per environment):** `RAW` and `ANALYTICS` per env → e.g. `DEV_RAW`, `DEV_ANALYTICS`, `PROD_RAW`, `PROD_ANALYTICS`.
Schema in RAW: `INSURANCE` (named after the source system; holds the stage, file formats and raw tables).
Schemas in ANALYTICS: `STAGING`, `MARTS`, `SEMANTIC` (semantic view + agent), `DQ`, `GOVERNANCE` (masking policies, kept apart from data so policy ownership can be separated later).

### Step 2 — Loading RAW (from the dbt project)
- RAW tables, the internal stage and the file formats are created in platform setup. CSV format: header skip, `FIELD_OPTIONALLY_ENCLOSED_BY='"'` (customer names contain commas). JSON format: `STRIP_OUTER_ARRAY=TRUE`.
- Files are uploaded to the stage (Snowsight upload or `snow stage copy`). A dbt macro then runs `COPY INTO` for each table: `dbt run-operation load_raw`.
- RAW columns are **VARCHAR** (endorsements land in a `VARIANT`), plus `_file_name` and `_loaded_at`. Bad values never fail a load; typing happens in staging.
- `COPY INTO` is idempotent: load history skips files already loaded.

### Step 3 — Data discovery
`discovery/01_data_discovery.sql` (run as a Snowsight worksheet or Snowflake Notebook) profiles RAW: row counts, PK duplicates, orphan FKs, nulls, negative amounts, date-order checks, category values, out-of-term events. Its output is the evidence behind every cleanup rule in staging.

### Step 4 — Staging + cleanup (dbt)
| Model group | Materialization | What it does |
|---|---|---|
| `stg_*` (one per source) | view | `TRY_CAST` types, trim, dedupe (`QUALIFY ROW_NUMBER()`), type-signed endorsement amount, single-table flags (missing premium, invalid term, negative payment, sign mismatch) |
| `dq_*` | table | Quarantined rows (e.g. the duplicate claim) + a DQ summary (issue, row count, run time) |

Checks across tables (orphan FKs, out-of-term events) need the policy dates, so they're computed in the marts. An intermediate layer is added only if that logic grows.

### Step 5 — Marts (star schema, dbt tables)
- `dim_customer` (with a simple risk tier), `dim_policy` (with customer attributes and DQ flags), `dim_date`
- `fct_claims` (grain: claim), `fct_payments` (grain: payment), `fct_endorsements` (grain: endorsement). Orphans map to an **unknown member (-1)**, so totals still reconcile.
- **`fct_policy_performance` (grain: policy):** premium, adjusted premium, claims counted in the loss ratio, total claims, premium collected, open-claim amount. This is the **main table for the semantic view**. Premium lives at policy grain, so joining claims to policies would repeat the premium once per claim (fan-out) and inflate it. Pre-summing to policy grain means `SUM(premium)` and `SUM(claims)` are correct in any slice.

### Step 6 — Semantic view (built by dbt)
Built with the Snowflake Labs `dbt_semantic_view` package (`materialized='semantic_view'`), so it's versioned, tested and deployed with the rest of the project.
- **Tables and relationships:** `fct_policy_performance`, `fct_claims`, `fct_payments` → `dim_policy` → `dim_customer`; `dim_date`.
- **Dimensions:** policy type, state, industry, customer risk tier, effective month/year, claim status, claim month, payment month.
- **Metrics (defined once, reused everywhere):**
  - **Loss ratio** = `SUM(loss_ratio_claims) / SUM(premium)` (excludes pre-start claims and policies with a missing premium)
  - Adjusted loss ratio, collection rate, outstanding premium, claim count, open-claim exposure, total premium, total claims
- **Descriptions, synonyms** ("LR", "losses", "written premium") **and verified queries** for Q1–Q4, so Cortex Analyst answers consistently.

### Step 7 — Reporting layer: Streamlit in Snowflake (tentative)
- A Streamlit app that queries the semantic view, with pages for the four business questions: loss ratio by policy type, claims and premium-collected trends by segment, customer and policy-group risk, and portfolio profitability over time.
- It runs inside Snowflake as `ANALYST`-level access, so masking and grants apply automatically.
- The deploy pipeline goes Git → dbt project in Snowflake → a Snowflake Task scheduled as `SERVICE_ROLE`.

**Optional add-on: Snowflake CoWork** (same semantic view, no model changes)
- A **Cortex Agent** (`POLICY_PERFORMANCE_AGENT`) with one **Cortex Analyst tool** pointing at the semantic view, running on `ANALYTICS_WH`.
- Agent instructions state the metric definitions and caveats: written premium, pre-start claims excluded, collections exceed premium.
- Starter questions are the four business questions. Business users ask in plain English in CoWork; answers come back as charts and tables.
- Governance is inherited: the `customer_name` masking policy and role grants apply to agent answers automatically.

### Metric definitions (kept simple and documented)
- **Loss ratio (primary KPI)** = `SUM(claim_amount) / SUM(premium)`. This is the assignment's definition.
  - Claims: all statuses, deduplicated, excluding claims dated before the policy started (see §4).
  - Premium: the policy's written premium; policies with a missing premium are excluded from the denominator.
- **Adjusted loss ratio** (secondary) = claims / (premium + type-signed endorsement amounts).
- **Collection rate** = `SUM(payment_amount) / SUM(premium)`: how much of the written premium was collected.
- **Outstanding premium** = `GREATEST(premium − collected, 0)`. A high loss ratio *plus* unpaid premium = highest financial risk (Q3).
- Earned premium and calendar-vs-policy-year views → deferred to the deeper discussion.

---

## 4. Data quality policy: flag and quarantine, don't silently drop

- **Hard failures** (row can't be trusted at all: duplicate PK loser, unparseable key) → `DQ.quarantine_*` and excluded from marts.
- **Soft issues** (could be legitimate: negative payment, out-of-term claim, missing premium) → kept, with a boolean `is_*` flag so analysts can filter.
- dbt tests: `unique` and `not_null` on PKs, `relationships` for FKs, `accepted_values` for categories, plus custom tests (`expiration >= effective`, amount sign checks).
  - Tests on **sources/RAW** are `severity: warn` (we know the source is dirty); tests on **staging outputs and marts** are `severity: error` (the cleaned layers must be clean).

### Judgment calls

**Endorsements: trust the type, not the sign.**
- Standard convention: an endorsement amount is the change in premium. Coverage Increase = additional premium (+); Coverage Reduction and Cancellation = return premium (−).
- Rule: `signed_amount = ABS(amount) × (+1 for Increase, −1 for Reduction/Cancellation)`. The raw amount is kept, with `is_sign_mismatch` set.
- Why: the type is a deliberate business classification, while the sign is where entry/ETL errors happen (and the README calls out negative amounts as an intentional DQ issue). Trusting the sign would mean ~45% of coverage increases *lower* premium, which makes no business sense.
- Impact is small: endorsements only feed the *adjusted* loss ratio, not the primary KPI.

**Claims outside the policy term: exclude claims before the start, keep claims after the end.**
- *Before effective date (60):* the policy didn't exist yet, so the loss can't belong to it. Kept in `fct_claims` with a flag, excluded from the loss ratio, and counted in the DQ summary.
- *After expiration (118):* the data doesn't say whether `claim_date` is the loss date or the report date. Claims are often reported after a policy ends for a loss that happened during the term, so these are kept and flagged.
- *Policy with an invalid term (policy 21):* no in/out-of-term check is possible; its claims are kept and flagged.

**This choice materially moves the KPI, so the README shows the sensitivity:**

| Claims included | Portfolio loss ratio |
|---|---|
| All claims | 0.88 |
| **Excluding claims before the start (chosen)** | **0.77** |
| Strictly in-term only | 0.52 |

### Limitations of claims / premium (to document)
- **Written, not earned premium.** Policies still in force look better than they will end up; earned premium is the industry standard for profitability.
- **Claim amount basis unknown.** Open and Pending claims (~70%) may be reserves or estimates that will change, so the ratio is closer to "incurred" than "paid".
- **No expenses.** A loss ratio isn't the full profitability picture (the combined ratio adds expenses).
- **Collections don't reconcile to premium.** 643 of 1,002 policies collected more than their written premium, and term length doesn't explain it. Possible causes: overpayments, duplicate payments, or premium being a per-period figure. It's reported and flagged, not adjusted, and is a good follow-up question for the business.

---

## 5. Production operations in Snowflake

**RBAC (functional roles, rolled up to SYSADMIN)**
| Role | Who | Access |
|---|---|---|
| `SERVICE_ROLE` | dbt / CI and the loader (service user `DBT_SVC`) | Owns ANALYTICS objects (incl. the semantic view); read/write RAW; uses LOAD_WH and TRANSFORM_WH |
| `DEVELOPER` | Engineers | Full on DEV; read-only on PROD (changes ship via CI only); can run discovery on RAW; inherits ANALYST |
| `ANALYST` | Product Analytics / business users | `SELECT` on `MARTS`, `DQ` and the semantic view; `USAGE` on the Cortex Agent; no RAW/STAGING; uses ANALYTICS_WH |

Grants use `GRANT ... ON FUTURE TABLES/VIEWS IN SCHEMA`, so new dbt models get the right access automatically. The service user authenticates with key-pair auth, not a password.

**Warehouses (separated by workload)**
| Warehouse | Size | Auto-suspend | Why |
|---|---|---|---|
| `LOAD_WH` | XS | 60s | Short bursty COPY jobs; suspend fast |
| `TRANSFORM_WH` | XS (raise to S if needed) | 60s | dbt runs are batch; no value in staying warm |
| `ANALYTICS_WH` | XS, multi-cluster 1–2 (Enterprise) | 300s | Serves the agent's SQL and analysts; keeps the cache warm; scales out for concurrency, not up |

All warehouses: `AUTO_RESUME=TRUE`, `INITIALLY_SUSPENDED=TRUE`, plus `STATEMENT_TIMEOUT_IN_SECONDS` to stop runaway queries.

**Cost control**
- An account-level monthly resource monitor (notify at 75%, suspend at 100%, suspend immediately at 110%), plus a smaller monitor on ANALYTICS_WH.
- Resource monitors only cover warehouses, so **Cortex/AI usage from CoWork is tracked with a Snowflake Budget**.
- `QUERY_TAG` set per dbt model for cost attribution.

**Sensitive data example:** a dynamic **masking policy** on `dim_customer.customer_name`, applied by a dbt post-hook so it survives table rebuilds. `DEVELOPER` and `SERVICE_ROLE` see the clear value; `ANALYST` sees a masked or hashed value, **including in CoWork answers**. (Extension: tag-based masking, row access policy by state.)

**Monitor / troubleshoot / deploy**
- *Monitor:* dbt test results and `source freshness`; the DQ summary table; `ACCOUNT_USAGE` (`COPY_HISTORY`, `QUERY_HISTORY`, `WAREHOUSE_METERING_HISTORY`, Cortex usage views); Snowflake Alerts or email on failures and monitor thresholds.
- *Troubleshoot:* find a failing model via its query tag → Query Profile; DQ quarantine tables show exactly which rows were rejected and why. For a wrong agent answer, inspect the SQL Cortex Analyst generated, then add a verified query or synonym to the semantic view.
- *Deploy:* Git → PR → CI runs `dbt build` against an isolated CI schema (later: only modified models) → merge → prod job runs as `SERVICE_ROLE`. The semantic view deploys with dbt. Platform objects (roles, warehouses, monitors, the agent) live as versioned SQL scripts (Terraform later). Dev uses a **zero-copy clone** of PROD_RAW.

---

## 6. Key decisions and why not the alternatives

| Decision | Chosen | Not chosen and why |
|---|---|---|
| Transformation tool | **dbt, developed locally, deployed and scheduled as a dbt project in Snowflake** | *Snowflake-native SQL/Tasks only:* weaker testing, docs, lineage and env promotion. *External orchestrator (Airflow, dbt Cloud):* another platform to run, secure and pay for. Running inside Snowflake keeps scheduling, logs, permissions and cost in one place |
| Loading RAW | **Stage + `COPY INTO`, triggered by `dbt run-operation`** | *dbt seeds:* CSV only (can't load `endorsements.json`), infer types (dirty values can break the load or be typed wrong), and are meant for small static reference data, not source data |
| Layering | **RAW → staging (with cleanup) → marts → semantic view** | *Transform straight into marts:* no replayable raw copy and harder debugging. *Separate intermediate layer:* not needed at this size |
| Bad data | **Flag and quarantine** | *Drop rows:* hides problems and distorts totals (e.g. ~40% of claims are out of term). *Fix in place:* invents data, e.g. a zero premium would break loss ratios |
| Endorsement sign | **Derive from type** | *Trust the sign:* ~45% of coverage increases would lower premium. *Drop mismatches:* loses ~half the endorsements |
| Out-of-term claims | **Exclude only claims before the start** | *Keep all:* counts losses with no coverage. *In-term only:* drops 118 likely late-reported claims and understates losses (0.52 vs 0.77) |
| RAW typing | **VARCHAR/VARIANT, cast in staging** | *Strict types at load:* one bad value fails the whole file |
| Modeling | **Star schema + policy-grain performance fact** | *Pre-aggregated reporting marts per question:* the semantic view now does slicing and aggregation, so per-question tables would duplicate metric logic. *One Big Table:* fan-out risk and no reuse. *Data Vault:* overkill for 5 sources |
| Metric layer | **Snowflake semantic view** | *Metrics in a BI tool:* locked to that tool and invisible to Cortex. *Metrics hard-coded in mart columns:* can't be re-sliced, and every new question needs a new table |
| Reporting front end (tentative) | **Streamlit in Snowflake, reading the semantic view** | *CoWork agent:* strong for open-ended questions; an easy add-on on the same semantic view if time allows. *External BI tool:* another licence and another place to manage access. *Snowsight dashboard:* quick, but limited layout and interactivity |
| Ingestion at scale | **Batch `COPY INTO` now** | *Snowpipe / external stage on S3:* the right next step for continuous files, unnecessary for a one-time batch |
| Environments | **Database per env, one account** | *Account per env:* stronger isolation but too much overhead for this scope (worth mentioning for regulated prod) |
| Warehouses | **Separate per workload** | *One shared warehouse:* BI and ETL compete for compute and cost can't be attributed |
| PII protection | **Dynamic masking policy** | *Secure views / split PII table:* more objects to maintain, easy to bypass if someone is granted the base table, and wouldn't carry through to CoWork answers as cleanly |
| Mart materialization | **Tables (full refresh)** | *Incremental:* unnecessary at ~5k rows; the facts are designed so switching to incremental on `_loaded_at` is a config change |

---

## 7. Implementation steps (in order)

```
repo/
├─ README.md                    # design doc: decisions, assumptions, DQ findings, how to run
├─ platform/                    # run once as ACCOUNTADMIN/SYSADMIN, in order
│  ├─ 01_roles_and_users.sql
│  ├─ 02_warehouses.sql
│  ├─ 03_cost_controls.sql       # resource monitors + budget
│  ├─ 04_databases_schemas_grants.sql
│  ├─ 05_stage_file_formats_raw_tables.sql
│  ├─ 06_masking_policy.sql      # policy object; applied by a dbt post-hook
│  └─ 07_cortex_agent.sql        # agent + grants (after the semantic view exists)
├─ discovery/
│  └─ 01_data_discovery.sql      # profiling queries against RAW
└─ dbt/
   ├─ dbt_project.yml, profiles.yml (dev/prod targets), packages.yml (dbt_semantic_view)
   ├─ macros/load_raw.sql        # COPY INTO for each RAW table
   ├─ models/staging/            # sources.yml + stg_*.sql + tests
   ├─ models/dq/                 # quarantine + DQ summary
   ├─ models/marts/              # dims, facts, fct_policy_performance, schema.yml with docs + tests
   ├─ models/semantic/           # semantic view model
   ├─ tests/                     # custom singular tests
   └─ analyses/                  # SQL answering Q1–Q4 (used to check agent answers)
```

1. **Snowflake setup:** roles, warehouses, cost controls, databases/schemas, future grants, stage, file formats, RAW tables, masking policy.
2. **Load RAW from dbt:** upload files to the stage → `dbt run-operation load_raw`; check row counts against the source files.
3. **Data discovery:** run `discovery/01_data_discovery.sql`; confirm it reproduces the §2 findings.
4. **Staging + cleanup:** `stg_*` models, quarantine and DQ summary, tests.
5. **Marts:** dims, facts, `fct_policy_performance`; masking post-hook; error-level tests.
6. **Semantic view:** dimensions, metrics, relationships, synonyms, verified queries for Q1–Q4.
7. **CoWork:** create the Cortex Agent on the semantic view, grant it to `ANALYST`, and test Q1–Q4.
8. **Write-up:** README with decisions, assumptions, DQ findings, loss-ratio sensitivity and the ops narrative.

---

## 8. Verification

- **Load:** RAW row counts match the files (claims 425, customers 352, payments 3,554, policies 1,004, endorsements 50).
- **Discovery:** discovery SQL reproduces the §2 counts.
- **dbt:** `dbt build` passes; source warnings match the known DQ issues; staging and mart tests are green.
- **Reconciliation:** raw count = curated count + quarantined count per entity (claims 425 = 424 + 1). Premium and claim totals match between RAW and marts.
- **Metrics:** a direct `SEMANTIC_VIEW(...)` query returns the same portfolio loss ratio as the `analyses/` SQL (**0.77**), and the same results by policy type.
- **CoWork:** as `ANALYST`, ask Q1–Q4. Answers match the `analyses/` results, and customer names come back masked.
- **Security:** `USE ROLE ANALYST` → selecting from RAW/STAGING is denied. `USE ROLE DEVELOPER` → names visible.
- **Ops:** `SHOW WAREHOUSES` (auto-suspend/resume values), `SHOW RESOURCE MONITORS`, `SHOW GRANTS TO ROLE ...`.

---

## 9. Deferred to the deeper technical discussion
Earned vs written premium and calendar vs policy-year loss ratios; SCD2 snapshots for policy changes; incremental and Snowpipe ingestion at scale; access-role (database role) layering for RBAC; tag-based masking and row access policies; Terraform/CI details; evaluating and tuning agent answers (verified-query coverage); adding Cortex Search for unstructured documents such as policy forms or claim notes; why collections exceed written premium.
