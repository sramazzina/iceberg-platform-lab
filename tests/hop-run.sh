#!/usr/bin/env bash
# Checks hop/run.sh and make hop-run without Hop artifacts (spec
# 2026-11-13-hop-native-spark-design, section 5.1). Needs the running stack (make up) with
# at least one catalog. Removes its dummy files and hop-env.json at the end.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"
unset PIPELINE PACKAGE CATALOG JAR RUN_CONFIG

jar=test-dummy.jar
pkg=test-dummy.zip
env_file=hop/env/hop-env.json
cleanup() { rm -f "hop/dist/$jar" "hop/dist/$pkg" "$env_file"; }
trap cleanup EXIT

# hop_run VAR=VALUE...: runs hop/run.sh with these variables; prints the output and exit=<code>.
hop_run() {
  local out rc=0
  out=$(env "$@" hop/run.sh 2>&1 </dev/null) || rc=$?
  printf '%s\nexit=%s' "$out" "$rc"
}

echo "hop-run: input checks"
out=$(hop_run PACKAGE="$pkg" JAR="$jar")
assert_contains "$out" "set PIPELINE" "PIPELINE missing: message"
assert_contains "$out" "exit=2" "PIPELINE missing: exit 2"
out=$(hop_run PIPELINE=p.hpl JAR="$jar")
assert_contains "$out" "set PACKAGE" "PACKAGE missing: message"
out=$(hop_run PIPELINE=p.hpl PACKAGE="$pkg" JAR=missing.jar)
assert_contains "$out" "hop/dist/missing.jar not found" "jar missing: message"
assert_contains "$out" "exit=2" "jar missing: exit 2"
out=$(make -s hop-run PACKAGE="$pkg" JAR="$jar" 2>&1 </dev/null || true)
assert_contains "$out" "set PIPELINE" "make hop-run calls hop/run.sh"

touch "hop/dist/$jar" "hop/dist/$pkg"
assert_eq "$(docker compose exec -T spark test -r "/workspace/hop/dist/$jar" && echo readable)" \
  "readable" "spark reads hop/dist"

echo "hop-run: catalog choice"
configured=$(docker compose exec -T spark sed -nE \
  's/^spark\.sql\.catalog\.([A-Za-z0-9_]+)[[:space:]].*/\1/p' /opt/spark/conf/spark-defaults.conf)
count=$(grep -c . <<<"$configured" || true)
first=$(head -n1 <<<"$configured")
if ((count == 0)); then
  fail "the running stack has no catalog: add one to COMPOSE_PROFILES, then run make up"
  finish
fi

out=$(hop_run PIPELINE=p.hpl PACKAGE="$pkg" JAR="$jar" CATALOG=nosuchcatalog)
assert_contains "$out" "catalog 'nosuchcatalog' is not configured" "unknown catalog: message"
assert_contains "$out" "$first" "unknown catalog: the message lists the configured catalogs"
assert_contains "$out" "exit=2" "unknown catalog: exit 2"

out=$(hop_run PIPELINE=p.hpl PACKAGE="$pkg" JAR="$jar")
if ((count == 1)); then
  assert_contains "$out" "hop-run: catalog $first" "one catalog: chosen automatically"
else
  assert_contains "$out" "several catalogs are configured" "several catalogs: message"
  assert_contains "$out" "exit=2" "several catalogs: exit 2"
fi

echo "hop-run: hop-env.json and exit code"
rm -f "$env_file"
out=$(hop_run PIPELINE=p.hpl PACKAGE="$pkg" JAR="$jar" CATALOG="$first")
assert_eq "$(jq -r '[.variables[].name] | join(",")' "$env_file" 2>&1)" "LAKE_CATALOG,HOP_DATA" \
  "hop-env.json has only LAKE_CATALOG and HOP_DATA (no secret)"
assert_eq "$(jq -r '.variables[] | select(.name == "LAKE_CATALOG") | .value' "$env_file" 2>&1)" \
  "$first" "LAKE_CATALOG is the chosen catalog"
assert_eq "$(jq -r '.variables[] | select(.name == "HOP_DATA") | .value' "$env_file" 2>&1)" \
  "file:///workspace/hop/out" "HOP_DATA"
assert_contains "$out" "hop-run: catalog $first" "the run starts spark-submit"
assert_not_contains "$out" "exit=0" "spark-submit fails on the dummy jar: non-zero exit propagates"

finish
