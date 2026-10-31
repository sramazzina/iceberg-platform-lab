-- Fails (returns a row) when the total revenue of revenue_by_nation differs from the
-- total computed from stg_lineitem. The tolerance covers the rounding per nation.
with marts as (
    select sum(revenue) as total from {{ ref('revenue_by_nation') }}
),
staging as (
    select cast(sum(extended_price * (1 - discount)) as decimal(18, 2)) as total
    from {{ ref('stg_lineitem') }}
)
select marts.total as marts_total, staging.total as staging_total
from marts cross join staging
where abs(marts.total - staging.total) > 1
