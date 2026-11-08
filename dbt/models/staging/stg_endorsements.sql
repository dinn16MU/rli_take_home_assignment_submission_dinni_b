-- The amount's sign doesn't follow any consistent rule, so the TYPE decides it:
-- Coverage Increase adds premium (+); Reduction and Cancellation return premium (-).
select
    raw_data:endorsement_id::number                 as endorsement_id,
    raw_data:policy_id::number                      as policy_id,
    raw_data:endorsement_type::string               as endorsement_type,
    try_to_date(raw_data:endorsement_date::string)  as endorsement_date,
    raw_data:endorsement_amount::number(12, 2)      as amount_as_given,

    case
        when raw_data:endorsement_type::string = 'Coverage Increase'
            then abs(raw_data:endorsement_amount::number(12, 2))
        else -abs(raw_data:endorsement_amount::number(12, 2))
    end                                             as signed_amount,

    -- Flag: the given sign disagrees with the type
    case
        when raw_data:endorsement_type::string = 'Coverage Increase'
            then raw_data:endorsement_amount::number(12, 2) < 0
        else raw_data:endorsement_amount::number(12, 2) > 0
    end                                             as is_sign_mismatch,

    _loaded_at
from {{ source('insurance', 'endorsements') }}
