#!/usr/bin/env bash
# End-to-end ELT test on one catalog (spec 2026-10-30-dbt-elt, section 7): load up to
# 1996-12-31, dbt build, full load, dbt run (fct_lineitem merges only the new rows), read
# a mart through the Thrift Server (JDBC), clean. Usage: tests/elt.sh CATALOG
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
source "$ROOT/tests/lib/spark-sql.sh"
source "$ROOT/tests/lib/s3-left.sh"
cd "$ROOT"
if [[ -v COMPOSE_PROFILES ]]; then keep=$COMPOSE_PROFILES; fi
set -a; source .env; set +a
if [[ -v keep ]]; then COMPOSE_PROFILES=$keep; fi

catalog=${1:-}
case $catalog in
  polaris | nessie | rest) ;;
  *) echo "usage: tests/elt.sh polaris|nessie|rest" >&2; exit 2 ;;
esac
sf=0.01
until=1996-12-31
trap 'make -s tpch-clean CATALOG="$catalog" >/dev/null 2>&1 || echo "  warn - make tpch-clean CATALOG=$catalog failed"' EXIT

# value SQL: the single value of a query that returns concat('v=', ...).
value() { spark_sql "$1" | sed -n 's/^v=//p'; }
fct=$catalog.tpch_marts.fct_lineitem

echo "elt $catalog"
make -s tpch-gen SF=$sf >/dev/null 2>&1 || fail "make tpch-gen SF=$sf"
out=$(make -s tpch-load CATALOG="$catalog" SF=$sf UNTIL=$until 2>&1 || echo "tpch-load failed")
assert_not_contains "$out" "tpch-load failed" "make tpch-load UNTIL=$until"
out=$(make -s dbt CATALOG="$catalog" ARGS=build 2>&1 || echo "dbt build failed")
assert_contains "$out" "Completed successfully" "dbt build (models and tests)"
assert_not_contains "$out" "dbt build failed" "dbt build exit code"
assert_eq "$(value "SELECT concat('v=', count(*)) FROM $fct")" \
  "$(value "SELECT concat('v=', count(*)) FROM $catalog.tpch_raw.lineitem")" "fct_lineitem has every raw line item"
assert_eq "$(value "SELECT concat('v=', max(order_date) <= DATE'$until') FROM $fct")" "true" "fct_lineitem stops at $until"
# last: the operation of the last snapshot of fct_lineitem. Do not count snapshots: Nessie
# returns only the snapshot of its current commit (NOTES F7, S8).
last() { value "SELECT concat('v=', operation) FROM $fct.snapshots ORDER BY committed_at DESC LIMIT 1"; }
assert_eq "$(last)" "overwrite" "dbt build creates fct_lineitem (overwrite: table replace)"

out=$(make -s tpch-load CATALOG="$catalog" SF=$sf 2>&1 || echo "tpch-load failed")
assert_not_contains "$out" "tpch-load failed" "make tpch-load (full)"
out=$(make -s dbt CATALOG="$catalog" ARGS=run 2>&1 || echo "dbt run failed")
assert_contains "$out" "Completed successfully" "dbt run (incremental)"
assert_not_contains "$out" "dbt run failed" "dbt run exit code"
assert_eq "$(value "SELECT concat('v=', count(*)) FROM $fct")" \
  "$(value "SELECT concat('v=', count(*)) FROM $catalog.tpch_raw.lineitem")" "fct_lineitem has every raw line item after the merge"
assert_eq "$(value "SELECT concat('v=', count(*) = count(DISTINCT order_key, line_number)) FROM $fct")" "true" "the merge gives no duplicate key"
assert_eq "$(last)" "append" "the incremental run merges into fct_lineitem (append: only new rows)"
assert_eq "$(value "SELECT concat('v=', count(*)) FROM $catalog.tpch_marts.revenue_by_nation")" "25" "revenue_by_nation has 25 nations"
assert_eq "$(value "SELECT concat('v=', count(*) > 0) FROM $catalog.tpch_staging.stg_orders")" "true" "a staging model reads from another Spark application"

jdbc=$(docker compose exec -T spark-thrift beeline -u 'jdbc:hive2://127.0.0.1:10000/;auth=noSasl' -n spark \
  --silent=true --showHeader=false --outputformat=tsv2 \
  -e "SELECT count(*) FROM $catalog.tpch_marts.revenue_by_nation" 2>&1 || echo "beeline failed")
# beeline prints its prompt in front of the value in non-interactive mode.
assert_eq "$(grep -Ex '(0: jdbc:[^>]*> )?25' <<<"$jdbc" | sed 's/^.*> //' || true)" "25" "a JDBC client reads the mart with its three-part name"

out=$(make -s tpch-clean CATALOG="$catalog" 2>&1 || echo "tpch-clean failed")
assert_not_contains "$out" "tpch-clean failed" "make tpch-clean"
assert_not_contains "$out" "tpch-clean: FAIL" "make tpch-clean leaves no file"
assert_eq "$(s3_left "$catalog")" "0" "no object left under $catalog/ in a tpch_ namespace"

finish
