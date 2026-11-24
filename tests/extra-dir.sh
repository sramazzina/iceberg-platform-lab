#!/usr/bin/env bash
# Checks the extra directory of the Spark services (spec 2026-11-24-extra-jdbc-sources,
# sections 4.2-4.4): mount, driver class path, conf/*.conf appended, host.docker.internal.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"

tmp=$(mktemp -d)
empty=$(mktemp -d)
trap 'rm -rf "$tmp" "$empty"' EXIT
mkdir -p "$tmp/jars" "$tmp/conf"
printf 'spark.lab.extra.probe    ok\n' >"$tmp/conf/10-probe.conf"
printf 'spark.lab.extra.ignored    yes\n' >"$tmp/conf/notes.txt"
chmod 755 "$tmp" "$tmp/jars" "$tmp/conf" "$empty"
chmod 644 "$tmp"/conf/*

# conf DIR: the rendered spark-defaults.conf with LAB_EXTRA_DIR=DIR and catalog nessie.
conf() {
  LAB_EXTRA_DIR="$1" docker compose run --rm --no-deps -T -e LAB_CATALOGS=nessie spark \
    cat /opt/spark/conf/spark-defaults.conf 2>/dev/null || echo "command failed"
}

echo "extra directory"
cfg=$(COMPOSE_PROFILES='*' docker compose config --format json)
for service in spark spark-thrift; do
  assert_eq "$(jq -r --arg s "$service" '.services[$s].volumes[] | select(.target == "/opt/lab-extra") | .read_only' <<<"$cfg")" \
    "true" "$service mounts the extra directory read-only"
  assert_contains "$(jq -r --arg s "$service" '.services[$s].extra_hosts | tostring' <<<"$cfg")" \
    "host.docker.internal" "$service resolves host.docker.internal"
done

with=$(conf "$tmp")
assert_contains "$with" "spark.lab.extra.probe    ok" "a .conf file is appended"
assert_not_contains "$with" "spark.lab.extra.ignored" "a file without .conf is ignored"
assert_contains "$with" "spark.driver.extraClassPath    /opt/lab-extra/jars/*" "the jars directory is on the driver class path"
assert_contains "$with" "spark.sql.catalog.nessie.uri" "the catalog block is still rendered"

none=$(conf "$empty")
assert_not_contains "$none" "command failed" "an empty extra directory is accepted"
assert_not_contains "$none" "spark.lab.extra" "an empty extra directory adds nothing"

val=$(LAB_EXTRA_DIR="$tmp" docker compose run --rm --no-deps -T -e LAB_CATALOGS= spark \
  spark-sql -e 'SET spark.lab.extra.probe' 2>/dev/null || echo "spark-sql failed")
match=$(grep -E '^spark\.lab\.extra\.probe[[:space:]]+ok$' <<<"$val" || echo "no match")
assert_contains "$match" "spark.lab.extra.probe" "spark-sql sees the appended property with its value"

hosts=$(LAB_EXTRA_DIR="$empty" docker compose run --rm --no-deps -T spark getent hosts host.docker.internal 2>/dev/null || echo "none")
assert_contains "$hosts" "host.docker.internal" "host.docker.internal resolves in the container"

finish
