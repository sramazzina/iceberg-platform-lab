-- Incremental: an incremental run merges only the line items of orders that are newer
-- than the newest order of the table (spec 2026-10-30-dbt-elt, section 6.5).
{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['order_key', 'line_number']
) }}

select
    l.order_key,
    l.line_number,
    o.customer_key,
    o.order_date,
    l.quantity,
    l.extended_price,
    l.discount,
    cast(l.extended_price * (1 - l.discount) as decimal(18, 2)) as net_revenue
from {{ ref('stg_lineitem') }} as l
join {{ ref('stg_orders') }} as o on l.order_key = o.order_key
{% if is_incremental() %}
where o.order_date > (select max(order_date) from {{ this }})
{% endif %}
