-- Payments = premium collected. Payments outside the policy term are kept
-- (advance deposits and late installments are plausible) and labeled.
select
    pay.payment_id,
    pay.policy_id,
    p.customer_id,
    pay.payment_date,
    date_trunc('month', pay.payment_date)   as payment_month,
    pay.payment_amount,
    pay.is_negative_amount,

    case
        when p.is_invalid_term                      then 'invalid policy term'
        when pay.payment_date < p.effective_date    then 'before policy start'
        when pay.payment_date > p.expiration_date   then 'after policy end'
        else 'during policy'
    end                                             as payment_timing

from {{ ref('stg_payments') }} pay
join {{ ref('stg_policies') }} p
    on pay.policy_id = p.policy_id
