-- Net revenue (extended price less discount) and order count per nation.
select
    n.nation_name,
    r.region_name,
    cast(sum(l.extended_price * (1 - l.discount)) as decimal(18, 2)) as revenue,
    count(distinct o.order_key) as order_count
from {{ ref('stg_lineitem') }} as l
join {{ ref('stg_orders') }} as o on l.order_key = o.order_key
join {{ ref('stg_customer') }} as c on o.customer_key = c.customer_key
join {{ ref('stg_nation') }} as n on c.nation_key = n.nation_key
join {{ ref('stg_region') }} as r on n.region_key = r.region_key
group by n.nation_name, r.region_name
