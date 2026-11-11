#!/usr/bin/env bash
# Writes the Trino configuration for the catalogs that are on (LAB_CATALOGS, a copy of
# COMPOSE_PROFILES) to /tmp/trino-etc, then starts Trino (single node). When arguments are
# given, runs them instead (tests/trino-config.sh). /etc/trino belongs to the image user
# trino; the container runs with LAB_UID, so the configuration goes to /tmp.
# The files hold no secret: the catalog files read them with ${ENV:NAME}.
set -euo pipefail

src=/lab
etc=/tmp/trino-etc
data=/tmp/trino-data
secrets=${LAB_TRINO_SECRETS:-/run/lab-secrets/trino_user.env}

IFS=', ' read -ra list <<<"${LAB_CATALOGS:-}"

rm -rf "$etc"
mkdir -p "$etc/catalog" "$data"

for profile in "${list[@]}"; do
  case $profile in
    # Profiles of services, not catalogs.
    thrift | trino) continue ;;
    '*')
      echo "trino-entrypoint: COMPOSE_PROFILES='*' is not supported for Trino; list the catalogs" >&2
      continue ;;
    # The profile baseline starts the rest fixture: Spark and Trino name the catalog rest.
    baseline) catalog=rest ;;
    *) catalog=$profile ;;
  esac
  if [[ ! -f $src/catalog/$catalog.properties ]]; then
    echo "trino-entrypoint: no Trino catalog for profile '$profile' (trino/catalog/$catalog.properties)" >&2
    continue
  fi
  if [[ $catalog == polaris ]]; then
    if [[ ! -f $secrets ]]; then
      echo "trino-entrypoint: polaris is selected but secrets/trino_user.env (secrets/rustfs/ on the RustFS variant) is missing: run make up (polaris-setup writes it)" >&2
      exit 1
    fi
    # Exported for ${ENV:...} in polaris.properties; never written to a file.
    set -a
    # shellcheck source=/dev/null
    source "$secrets"
    set +a
  fi
  cp "$src/catalog/$catalog.properties" "$etc/catalog/$catalog.properties"
  # S3-compatible storage: Trino rejects an empty s3.endpoint, so the lines are a fragment.
  if [[ -n ${S3_ENDPOINT:-} ]]; then
    cat "$src/catalog-s3-endpoint/$catalog.properties" >>"$etc/catalog/$catalog.properties"
  fi
done

# JVM options of the image default (core/docker/default/etc/jvm.config), with a fixed heap
# instead of -XX:MaxRAMPercentage, so that the heap does not follow the container limit.
cat >"$etc/jvm.config" <<EOF
-server
-agentpath:/usr/lib/trino/bin/libjvmkill.so
-Xmx${TRINO_HEAP:-2g}
-XX:G1HeapRegionSize=32M
-XX:+ExplicitGCInvokesConcurrent
-XX:+HeapDumpOnOutOfMemoryError
-XX:+ExitOnOutOfMemoryError
-XX:-OmitStackTraceInFastThrow
-XX:ReservedCodeCacheSize=256M
-XX:PerMethodRecompilationCutoff=10000
-XX:PerBytecodeRecompilationCutoff=10000
-Djdk.attach.allowAttachSelf=true
-Djdk.nio.maxCachedBufferSize=2000000
EOF

# Single node: coordinator and worker in one process. The query memory limits keep the
# Trino defaults (30% of the heap per node, 30% headroom), so they follow TRINO_HEAP.
cat >"$etc/config.properties" <<'EOF'
coordinator=true
node-scheduler.include-coordinator=true
http-server.http.port=8080
discovery.uri=http://localhost:8080
catalog.management=static
EOF

cat >"$etc/node.properties" <<EOF
node.environment=lab
node.data-dir=$data
node.id=\${ENV:HOSTNAME}
EOF

if (($# > 0)); then
  exec "$@"
fi

exec /usr/lib/trino/bin/launcher run --etc-dir "$etc"
