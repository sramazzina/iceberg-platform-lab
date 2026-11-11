#!/usr/bin/env bash
# Checks the trino service (spec 2026-11-11-trino-design, section 9.2). For each catalog that
# is on: Trino reads a table that Spark wrote, the JDBC metadata tables of Trino (the data
# of the DBeaver navigator) list the namespace and the table, and Spark reads a table that
# Trino wrote. The test tables and the namespace are removed at the end.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
source "$ROOT/tests/lib/spark-sql.sh"
cd "$ROOT"
if [[ -v COMPOSE_PROFILES ]]; then keep=$COMPOSE_PROFILES; fi
set -a; source .env; set +a
if [[ -v keep ]]; then COMPOSE_PROFILES=$keep; fi

ts=$(date +%s)
ns=trino_check

# trino_sql SQL: runs SQL with the Trino CLI in the trino container. Prints the rows as TSV
# without header; prints "trino failed" on a non-zero exit.
trino_sql() {
  docker compose exec -T trino trino --output-format TSV --execute "$1" 2>&1 || echo "trino failed"
}

touched=()
cleanup() {
  set +e
  local c purge
  for c in "${touched[@]}"; do
    # Nessie never deletes files (catalog-smoke.sh): drop without PURGE, then delete the files.
    purge=" PURGE"; [[ $c == nessie ]] && purge=""
    spark_sql "DROP TABLE IF EXISTS $c.$ns.from_spark_$ts$purge;
DROP TABLE IF EXISTS $c.$ns.from_trino_$ts$purge;
DROP NAMESPACE IF EXISTS $c.$ns" >/dev/null
    if [[ $c == nessie ]]; then
      docker compose exec -T spark aws s3 rm --recursive --quiet "s3://$S3_BUCKET/nessie/$ns/" >/dev/null 2>&1 \
        || echo "  warn - could not delete s3://$S3_BUCKET/nessie/$ns/"
    fi
  done
}
trap cleanup EXIT

echo "trino"
services=$(docker compose config --services)
for entry in nessie:nessie polaris:polaris rest-fixture:rest; do
  service=${entry%%:*}
  c=${entry#*:}
  grep -qx "$service" <<<"$services" || continue
  touched+=("$c")
  from_spark=$c.$ns.from_spark_$ts
  from_trino=$c.$ns.from_trino_$ts

  out=$(spark_sql "CREATE NAMESPACE IF NOT EXISTS $c.$ns;
CREATE TABLE $from_spark (id INT, name STRING) USING iceberg;
INSERT INTO $from_spark VALUES (1, 'spark');")
  assert_not_contains "$out" "spark-sql failed" "$c: Spark creates a table and writes one row"
  assert_eq "$(trino_sql "SELECT id, name FROM $from_spark")" $'1\tspark' "$c: Trino reads the row that Spark wrote"

  assert_eq "$(trino_sql "SELECT table_schem FROM system.jdbc.schemas WHERE table_catalog = '$c' AND table_schem = '$ns'")" \
    "$ns" "$c: system.jdbc.schemas lists the namespace (navigator)"
  assert_eq "$(trino_sql "SELECT table_name FROM system.jdbc.tables WHERE table_cat = '$c' AND table_schem = '$ns' AND table_name = 'from_spark_$ts'")" \
    "from_spark_$ts" "$c: system.jdbc.tables lists the table (navigator)"

  # CAST: the Iceberg connector has no bounded varchar; a literal is varchar(n).
  out=$(trino_sql "CREATE TABLE $from_trino AS SELECT 2 AS id, CAST('trino' AS varchar) AS name")
  assert_not_contains "$out" "trino failed" "$c: Trino creates a table with CREATE TABLE AS"
  assert_eq "$(spark_sql "SELECT concat('row=', id, ':', name) FROM $from_trino" | grep '^row=' || true)" \
    "row=2:trino" "$c: Spark reads the row that Trino wrote"
done
if ((${#touched[@]} == 0)); then
  echo "  warn - no catalog in COMPOSE_PROFILES: only the service checks ran"
fi

assert_eq "$(docker compose port trino 8080 2>&1)" "127.0.0.1:8080" "port 8080 published on 127.0.0.1 only"

if grep -qx polaris <<<"$services"; then
  creds=secrets/trino_user.env
  if grep -qx rustfs <<<"$services"; then creds=secrets/rustfs/trino_user.env; fi
  # The credentials go to the polaris container through its environment, not the command line.
  code=$( (set -a; source "$creds"; set +a
    docker compose exec -T -e POLARIS_TRINO_CLIENT_ID -e POLARIS_TRINO_CLIENT_SECRET polaris bash -c \
      'curl -sS -o /dev/null -w "%{http_code}" -X POST http://127.0.0.1:8181/api/catalog/v1/oauth/tokens \
        --user "$POLARIS_TRINO_CLIENT_ID:$POLARIS_TRINO_CLIENT_SECRET" \
        -d grant_type=client_credentials -d scope=PRINCIPAL_ROLE:ALL') 2>&1 || echo "token call failed")
  assert_eq "$code" "200" "polaris: a token call as trino_user works"
fi

finish
