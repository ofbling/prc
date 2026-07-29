with source as (
    select * from {{ source('tpch', 'customer') }}
),
renamed as (
    select
        c_custkey   as customer_key,
        c_name      as customer_name,
        c_address   as customer_address,
        c_phone     as phone
    from source
)
select * from renamed