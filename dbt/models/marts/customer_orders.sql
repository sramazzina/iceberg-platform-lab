-- One row per customer: order count, total spent, first and last order date.
select
    c.customer_key,
    c.customer_name,
    c.market_segment,
    count(o.order_key) as order_count,
    coalesce(sum(o.total_price), 0) as total_spent,
    min(o.order_date) as first_order_date,
    max(o.order_date) as last_order_date
from {{ ref('stg_customer') }} as c
left join {{ ref('stg_orders') }} as o on c.customer_key = o.customer_key
group by c.customer_key, c.customer_name, c.market_segment
