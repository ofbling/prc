with line_items as (
    select * from {{ ref('stg_tpch__lineitem') }}
),
orders as (
    select * from {{ ref('stg_tpch__orders') }}
)
select
    li.order_key,
    li.part_key,
    li.supplier_address,
    o.customer_key,
    o.order_date,
    li.quantity
from line_items li
inner join orders o on li.order_key = o.order_key