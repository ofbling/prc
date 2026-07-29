with customers as (
    select * from {{ ref('stg_tpch__customers') }}
)

select 
customer_key,
customer_name,
customer_address,
phone
from customers