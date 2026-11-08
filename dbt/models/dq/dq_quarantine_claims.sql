-- Claims removed from staging because their policy doesn't exist.
select
    c.*,
    'policy_id not found in policies' as quarantine_reason,
    current_timestamp()               as quarantined_at
from {{ source('insurance', 'claims') }} c
left join {{ source('insurance', 'policies') }} p
    on c.policy_id = p.policy_id
where p.policy_id is null
