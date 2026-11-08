select
    policy_id,
    customer_id,
    policy_type,
    effective_date,
    expiration_date,
    date_trunc('month', effective_date)   as effective_month,
    is_missing_premium,
    is_invalid_term
from {{ ref('stg_policies') }}
