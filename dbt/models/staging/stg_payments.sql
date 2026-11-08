-- Payments = premium collected from customers.
select
    try_to_number(payment_id)              as payment_id,
    try_to_number(policy_id)               as policy_id,
    try_to_date(payment_date)              as payment_date,
    try_to_number(payment_amount, 12, 2)   as payment_amount,

    -- Flag: likely refund or reversal (kept, not dropped)
    try_to_number(payment_amount, 12, 2) < 0   as is_negative_amount,

    _loaded_at
from {{ source('insurance', 'payments') }}
