#!/usr/bin/env bash
# Checks the dbt project and make dbt (spec 2026-10-30-dbt-elt, sections 6.5 and 6.6): the
# guards, dbt parse and dbt debug, and the default catalog of each target. No table is
# written. Run it with the profile thrift on.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"

echo "dbt project"
out=$(make -s dbt CATALOG=no-such ARGS=debug 2>&1 || true)
assert_contains "$out" "set CATALOG=polaris|nessie|rest" "an unknown catalog gives a clear message"
out=$(COMPOSE_PROFILES=nessie make -s dbt CATALOG=nessie ARGS=debug 2>&1 || true)
assert_contains "$out" "the Spark Thrift Server is off" "make dbt with the profile thrift off gives a clear message"

services=$(docker compose config --services)
for entry in nessie:nessie polaris:polaris rest-fixture:rest; do
  service=${entry%%:*}
  catalog=${entry#*:}
  grep -qx "$service" <<<"$services" || continue
  if make -s dbt CATALOG="$catalog" ARGS=parse >/dev/null 2>&1; then pass "dbt parse --target $catalog"; else fail "dbt parse --target $catalog"; fi
  assert_contains "$(make -s dbt CATALOG="$catalog" ARGS=debug 2>&1)" "All checks passed!" "dbt debug --target $catalog connects to spark-thrift"
  out=$(make -s dbt CATALOG="$catalog" ARGS="show --inline 'select current_catalog() as c' --output json" 2>&1 || true)
  assert_contains "$out" "\"c\": \"$catalog\"" "the target $catalog selects the Spark catalog $catalog"
done

finish
