-- Claims whose policy doesn't exist are dropped here and kept in dq_quarantine_claims.
-- This also removes the duplicate claim_id 1 (its second copy points to policy 999999).
select
    try_to_number(c.claim_id)            as claim_id,
    try_to_number(c.policy_id)           as policy_id,
    try_to_date(c.claim_date)            as claim_date,
    try_to_number(c.claim_amount, 12, 2) as claim_amount,
    trim(c.claim_status)                 as claim_status,
    c._loaded_at
from {{ source('insurance', 'claims') }} c
inner join {{ source('insurance', 'policies') }} p
    on c.policy_id = p.policy_id
