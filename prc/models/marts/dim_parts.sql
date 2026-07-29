with parts as (
    select * from {{ ref('stg_tpch__part') }}
)

select 
part_key,
part_name,
brand,
retail_price
from parts