select
    try_to_number(customer_id)  as customer_id,
    trim(customer_name)         as customer_name,
    trim(state)                 as state,
    trim(industry)              as industry,
    _loaded_at
from {{ source('insurance', 'customers') }}
