{{ config(materialized = 'semantic_view', copy_grants = true) }}

TABLES (
    policy_performance AS {{ ref('fct_policy_performance') }}
        PRIMARY KEY (policy_id)
        COMMENT = 'One row per policy: premium, claims, premium collected',
    policies AS {{ ref('dim_policy') }}
        PRIMARY KEY (policy_id)
        COMMENT = 'Policy attributes',
    customers AS {{ ref('dim_customer') }}
        PRIMARY KEY (customer_id)
        COMMENT = 'Customer attributes; customer_name is masked for analysts',
    claims AS {{ ref('fct_claims') }}
        PRIMARY KEY (claim_id)
        COMMENT = 'One row per claim',
    payments AS {{ ref('fct_payments') }}
        PRIMARY KEY (payment_id)
        COMMENT = 'One row per premium payment collected'
)

RELATIONSHIPS (
    performance_to_policy AS policy_performance (policy_id) REFERENCES policies,
    policy_to_customer    AS policies (customer_id)         REFERENCES customers,
    claim_to_policy       AS claims (policy_id)             REFERENCES policies,
    payment_to_policy     AS payments (policy_id)           REFERENCES policies
)

DIMENSIONS (
    policies.policy_type AS policies.policy_type
        WITH SYNONYMS ('line of business', 'product')
        COMMENT = 'Auto, Property, Liability, Marine, Workers Comp',
    policies.effective_month AS policies.effective_month
        COMMENT = 'Month the policy started',
    customers.state AS customers.state
        COMMENT = 'Customer state',
    customers.industry AS customers.industry
        COMMENT = 'Customer industry',
    customers.customer_name AS customers.customer_name
        COMMENT = 'Customer name (hashed for analysts)',
    claims.claim_status AS claims.claim_status
        COMMENT = 'Open, Pending or Closed',
    claims.claim_timing AS claims.claim_timing
        COMMENT = 'Claim date relative to the policy term',
    claims.claim_month AS claims.claim_month
        COMMENT = 'Month the claim was filed',
    payments.payment_month AS payments.payment_month
        COMMENT = 'Month the premium payment was collected'
)

METRICS (
    -- Primary KPI. Excludes claims dated before the policy started (in loss_ratio_claims)
    -- and policies with no premium (from both numerator and denominator).
    policy_performance.loss_ratio AS
        SUM(IFF(policy_performance.premium IS NOT NULL, policy_performance.loss_ratio_claims, 0))
        / NULLIF(SUM(policy_performance.premium), 0)
        WITH SYNONYMS ('LR', 'claims ratio')
        COMMENT = 'Claims / written premium',

    policy_performance.adjusted_loss_ratio AS
        SUM(IFF(policy_performance.premium IS NOT NULL, policy_performance.loss_ratio_claims, 0))
        / NULLIF(SUM(policy_performance.adjusted_premium), 0)
        COMMENT = 'Claims / premium after endorsements',

    policy_performance.total_premium AS SUM(policy_performance.premium)
        WITH SYNONYMS ('written premium')
        COMMENT = 'Written premium',

    policy_performance.total_premium_collected AS SUM(policy_performance.premium_collected)
        COMMENT = 'Premium collected from customers (payments)',

    policy_performance.collection_rate AS
        SUM(policy_performance.premium_collected) / NULLIF(SUM(policy_performance.premium), 0)
        COMMENT = 'Premium collected / written premium',

    policy_performance.open_claim_exposure AS SUM(policy_performance.open_claim_amount)
        COMMENT = 'Amount on Open and Pending claims',

    policy_performance.policy_count AS COUNT(policy_performance.policy_id)
        COMMENT = 'Number of policies',

    claims.claim_count AS COUNT(claims.claim_id)
        COMMENT = 'Number of claims',

    claims.total_claim_amount AS SUM(claims.claim_amount)
        COMMENT = 'Total claim amount (all claims)',

    payments.payments_total AS SUM(payments.payment_amount)
        COMMENT = 'Total premium payments collected'
)

COMMENT = 'Insurance policy performance: loss ratio, claims and premium collected'
