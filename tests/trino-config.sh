#!/usr/bin/env bash
# Checks the Trino configuration that trino/entrypoint.sh writes for a catalog selection
# (spec 2026-11-11-trino-design, section 9.1). No catalog runs.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"

# A dummy credentials file for the catalog polaris: test values, not secrets.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf 'POLARIS_TRINO_CLIENT_ID=test-client-id\nPOLARIS_TRINO_CLIENT_SECRET=test-client-secret\n' >"$tmp/trino_user.env"

# run_trino ARGS...: docker compose run of the service trino with the dummy credentials file.
# COMPOSE_PROFILES=trino: the service is in the profile trino.
run_trino() {
  COMPOSE_PROFILES=trino docker compose run --rm --no-deps -T \
    -v "$tmp:/run/test-secrets:ro" -e LAB_TRINO_SECRETS=/run/test-secrets/trino_user.env "$@"
}

# etc CATALOGS [S3_ENDPOINT [DOCKER_RUN_OPTION...]]: each file that the entrypoint writes, after a line "== <file>".
etc() {
  run_trino -e LAB_CATALOGS="$1" -e S3_ENDPOINT="${2:-}" -e S3_PATH_STYLE_ACCESS=true "${@:3}" trino \
    bash -c 'cd /tmp/trino-etc && for f in catalog/*.properties jvm.config config.properties node.properties; do if [[ -f $f ]]; then printf "== %s\n" "$f"; cat "$f"; fi; done' \
    2>/dev/null || echo "command failed"
}

# err CATALOGS: what the entrypoint prints on stderr, and "exit=<code>".
err() {
  run_trino -e LAB_CATALOGS="$1" trino true 2>&1 >/dev/null; echo "exit=$?"
}

echo "trino configuration"
# TRINO_HEAP=: empty, so the entrypoint uses its default 2g whatever .env sets.
none=$(etc "" "" -e TRINO_HEAP=)
assert_not_contains "$none" "command failed" "the entrypoint runs with no catalog"
assert_not_contains "$none" "== catalog/" "no catalog file with no catalog"
assert_contains "$none" "-Xmx2g" "jvm.config has the default heap"
assert_contains "$none" "coordinator=true" "single node: coordinator"
assert_contains "$none" "node-scheduler.include-coordinator=true" "single node: the coordinator runs tasks"
assert_contains "$none" "node.data-dir=/tmp/trino-data" "writable data directory"

heap=$(run_trino -e LAB_CATALOGS= -e TRINO_HEAP=1g trino cat /tmp/trino-etc/jvm.config 2>/dev/null || echo "command failed")
assert_contains "$heap" "-Xmx1g" "TRINO_HEAP sets -Xmx"

nessie=$(etc nessie)
assert_contains "$nessie" "== catalog/nessie.properties" "nessie file with nessie"
assert_contains "$nessie" "iceberg.rest-catalog.uri=http://nessie:19120/iceberg/main" "nessie through /iceberg/main"
assert_contains "$nessie" "fs.s3.enabled=true" "native S3 file system"
assert_not_contains "$nessie" "s3.endpoint" "no S3 endpoint on AWS"
assert_not_contains "$nessie" "== catalog/rest.properties" "no rest file with nessie only"

rest=$(etc baseline)
assert_contains "$rest" "== catalog/rest.properties" "the profile baseline gives the catalog rest"
assert_contains "$rest" "iceberg.rest-catalog.uri=http://rest-fixture:8181" "rest fixture URI"
assert_not_contains "$rest" "== catalog/baseline" "no catalog named baseline"

others=$(etc thrift,trino)
assert_not_contains "$others" "command failed" "the profiles thrift and trino run"
assert_not_contains "$others" "== catalog/" "no catalog file for the profiles thrift and trino"
assert_not_contains "$(err thrift,trino)" "no Trino catalog" "no warning for the profiles thrift and trino"
assert_contains "$(err no-such-catalog)" "no Trino catalog for profile 'no-such-catalog'" "a warning for an unknown profile"

polaris=$(etc polaris)
assert_contains "$polaris" "== catalog/polaris.properties" "polaris file with polaris"
assert_contains "$polaris" 'iceberg.rest-catalog.oauth2.credential=${ENV:POLARIS_TRINO_CLIENT_ID}:${ENV:POLARIS_TRINO_CLIENT_SECRET}' "the polaris credentials come from the environment"
assert_contains "$polaris" "iceberg.rest-catalog.vended-credentials-enabled=true" "polaris vends the S3 credentials"
assert_not_contains "$polaris" "test-client-secret" "no secret value in the configuration"
assert_not_contains "$polaris" "test-client-id" "no client id value in the configuration"

missing=$(COMPOSE_PROFILES=trino docker compose run --rm --no-deps -T -e LAB_CATALOGS=polaris \
  -e LAB_TRINO_SECRETS=/run/test-secrets/no-such-file trino true 2>&1; echo "exit=$?")
assert_contains "$missing" "secrets/trino_user.env" "polaris without credentials: a clear message"
assert_not_contains "$missing" "exit=0" "polaris without credentials: a non-zero exit code"

endpoint=$(etc nessie,polaris,baseline http://rustfs:9000)
assert_contains "$endpoint" 's3.endpoint=${ENV:S3_ENDPOINT}' "S3 endpoint with S3_ENDPOINT"
assert_contains "$endpoint" 's3.path-style-access=${ENV:S3_PATH_STYLE_ACCESS}' "path-style access with S3_ENDPOINT"
assert_not_contains "$endpoint" "http://rustfs:9000" "the endpoint stays an environment reference"
polaris_endpoint=$(sed -n '/^== catalog\/polaris.properties/,/^== /p' <<<"$endpoint")
assert_contains "$polaris_endpoint" "s3.endpoint=" "polaris gets the S3 endpoint"
assert_not_contains "$polaris_endpoint" "s3.aws-access-key" "polaris gets no static key (credential vending)"
nessie_endpoint=$(sed -n '/^== catalog\/nessie.properties/,/^== /p' <<<"$endpoint")
assert_contains "$nessie_endpoint" 's3.aws-access-key=${ENV:AWS_ACCESS_KEY_ID}' "nessie gets the keys of the user lab"

finish
