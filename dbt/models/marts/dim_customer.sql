{{ config(
    post_hook = "alter table {{ this }} modify column customer_name
                 set masking policy {{ target.database }}.governance.mp_customer_name force"
) }}

-- customer_name is masked for ANALYST (hash); DEVELOPER and SERVICE_ROLE see the real value.
select
    customer_id,
    customer_name,
    state,
    industry
from {{ ref('stg_customers') }}
