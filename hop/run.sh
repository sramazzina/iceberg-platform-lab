#!/usr/bin/env bash
# Runs an Apache Hop pipeline with the Hop native Spark engine in container spark (spec
# 2026-11-13-hop-native-spark-design, section 4.3). Runs on the host; make hop-run calls it.
# Input (environment): PIPELINE, PACKAGE, CATALOG (optional when one catalog is configured),
# JAR (default hop-native-spark4-submit.jar), RUN_CONFIG (default lab-spark).
# Exit: 2 for an input error; otherwise the exit code of spark-submit.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

pipeline=${PIPELINE:-}
package=${PACKAGE:-}
catalog=${CATALOG:-}
jar=${JAR:-hop-native-spark4-submit.jar}
run_config=${RUN_CONFIG:-lab-spark}

die() { echo "hop-run: $1" >&2; exit 2; }

[[ -n $pipeline ]] || die "set PIPELINE=<path of the pipeline in the package>, for example pipelines/x.hpl"
[[ -n $package ]] || die "set PACKAGE=<file in hop/dist>, for example project.zip"
[[ -f hop/dist/$jar ]] || die "hop/dist/$jar not found: copy the Hop fat jar to hop/dist/ (or set JAR)"
[[ -f hop/dist/$package ]] || die "hop/dist/$package not found: copy the Hop project package to hop/dist/"

# Catalog names only (lines spark.sql.catalog.<name> <class>): the file can hold the
# Polaris client secret.
if ! configured=$(docker compose exec -T spark sed -nE \
  's/^spark\.sql\.catalog\.([A-Za-z0-9_]+)[[:space:]].*/\1/p' \
  /opt/spark/conf/spark-defaults.conf 2>/dev/null </dev/null); then
  die "the container spark is not running: run make up"
fi
names=$(paste -sd ' ' <<<"$configured")

if [[ -z $catalog ]]; then
  case $(grep -c . <<<"$configured" || true) in
    0) die "no catalog is configured in spark: add nessie, polaris or baseline to COMPOSE_PROFILES, then run make up" ;;
    1) catalog=$configured ;;
    *) die "several catalogs are configured ($names): set CATALOG=<one of them>" ;;
  esac
elif ! grep -qxF -- "$catalog" <<<"$configured"; then
  die "catalog '$catalog' is not configured in spark (configured: ${names:-none})"
fi

mkdir -p hop/env
jq -n --arg catalog "$catalog" '{variables: [
  {name: "LAKE_CATALOG", value: $catalog,
   description: "Spark catalog of this run, configured in spark-defaults.conf"},
  {name: "HOP_DATA", value: "file:///workspace/hop/out",
   description: "Local data root for non-table outputs"}]}' >hop/env/hop-env.json

echo "hop-run: catalog $catalog, pipeline $pipeline, package $package" >&2
# </dev/null: docker compose exec -T forwards an open stdin (NOTES F8).
exec docker compose exec -T spark spark-submit \
  --master 'local[*]' \
  --class org.apache.hop.spark.run.MainSpark \
  "/workspace/hop/dist/$jar" \
  --HopProjectPackage="/workspace/hop/dist/$package" \
  --HopPipelinePath="$pipeline" \
  --HopRunConfigurationName="$run_config" \
  --HopConfigFile=/workspace/hop/env/hop-env.json </dev/null
