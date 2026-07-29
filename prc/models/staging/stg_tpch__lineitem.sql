with source as (
    select * from {{ source('tpch', 'lineitem') }}
),
renamed as (
    select
        l_orderkey     as order_key,
        l_partkey      as part_key,
        l_suppkey      as supplier_address,
        l_quantity     as quantity
    from source
)
select * from renamed