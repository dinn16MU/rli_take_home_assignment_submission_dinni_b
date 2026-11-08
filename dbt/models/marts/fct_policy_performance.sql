-- One row per policy with every input the loss ratio needs.
-- The ratio itself is calculated in the semantic view: SUM(claims) / SUM(premium).

with claims as (
    select
        policy_id,
        count(*)                                                        as claim_count,
        sum(claim_amount)                                               as total_claims,
        sum(iff(is_in_loss_ratio, claim_amount, 0))                     as loss_ratio_claims,
        sum(iff(claim_status in ('Open', 'Pending'), claim_amount, 0))  as open_claim_amount
    from {{ ref('fct_claims') }}
    group by policy_id
),

payments as (
    select
        policy_id,
        count(*)            as payment_count,
        sum(payment_amount) as premium_collected
    from {{ ref('fct_payments') }}
    group by policy_id
),

-- Endorsements dated after the policy ended are ignored: an expired policy can't be changed.
endorsements as (
    select
        e.policy_id,
        sum(e.signed_amount) as endorsement_change
    from {{ ref('stg_endorsements') }} e
    join {{ ref('stg_policies') }} p
        on e.policy_id = p.policy_id
    where e.endorsement_date <= p.expiration_date
    group by e.policy_id
)

select
    p.policy_id,
    p.customer_id,
    p.effective_date,
    date_trunc('month', p.effective_date)                   as effective_month,

    -- Premium (denominator)
    p.premium,
    p.premium + coalesce(e.endorsement_change, 0)           as adjusted_premium,

    -- Claims (numerator)
    coalesce(c.claim_count, 0)                              as claim_count,
    coalesce(c.total_claims, 0)                             as total_claims,
    coalesce(c.loss_ratio_claims, 0)                        as loss_ratio_claims,
    coalesce(c.open_claim_amount, 0)                        as open_claim_amount,

    -- Premium collected (cash view)
    coalesce(pay.payment_count, 0)                          as payment_count,
    coalesce(pay.premium_collected, 0)                      as premium_collected,
    coalesce(pay.premium_collected, 0) > p.premium          as is_over_collected,

    -- Data quality flags
    p.is_missing_premium,
    p.is_invalid_term

from {{ ref('stg_policies') }} p
left join claims       c   on p.policy_id = c.policy_id
left join payments     pay on p.policy_id = pay.policy_id
left join endorsements e   on p.policy_id = e.policy_id
