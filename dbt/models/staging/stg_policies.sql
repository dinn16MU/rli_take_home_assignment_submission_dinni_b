select
    try_to_number(policy_id)            as policy_id,
    try_to_number(customer_id)          as customer_id,
    trim(policy_type)                   as policy_type,
    try_to_date(effective_date)         as effective_date,
    try_to_date(expiration_date)        as expiration_date,
    try_to_number(premium, 12, 2)       as premium,

    -- Flags (kept, not dropped)
    premium is null                                                as is_missing_premium,
    try_to_date(expiration_date) < try_to_date(effective_date)     as is_invalid_term,

    _loaded_at
from {{ source('insurance', 'policies') }}
