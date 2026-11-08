-- Claim timing vs the policy term drives the loss-ratio rule:
-- claims BEFORE the policy started are excluded (no coverage existed);
-- claims AFTER it ended are included (late reporting is normal).
select
    c.claim_id,
    c.policy_id,
    p.customer_id,
    c.claim_date,
    date_trunc('month', c.claim_date)   as claim_month,
    c.claim_amount,
    c.claim_status,

    case
        when p.is_invalid_term                  then 'invalid policy term'
        when c.claim_date < p.effective_date    then 'before policy start'
        when c.claim_date > p.expiration_date   then 'after policy end'
        else 'during policy'
    end                                         as claim_timing,

    claim_timing <> 'before policy start'       as is_in_loss_ratio

from {{ ref('stg_claims') }} c
join {{ ref('stg_policies') }} p
    on c.policy_id = p.policy_id
