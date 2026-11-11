#!/bin/sh
# Idempotent Polaris setup (spec section 5.1; Trino spec 2026-11-11, section 8): catalog
# lab_catalog, principals spark_user and trino_user, principal roles spark_role and
# trino_role, catalog role lab_admin, and the grants. Writes the credentials to
# /secrets/spark_user.env and /secrets/trino_user.env. POSIX sh: the image has no bash and
# no jq, so the JSON answers are read with sed.
set -eu

API=http://polaris:8181
MGMT=$API/api/management/v1
ANSWER=/tmp/polaris-answer

fail() { echo "polaris-setup: $*" >&2; exit 1; }
# The answer file can hold the clientSecret.
trap 'rm -f "$ANSWER" /secrets/*.env.new' EXIT

: "${POLARIS_ROLE_ARN:?}" "${POLARIS_EXTERNAL_ID:?}" "${S3_BUCKET:?}" "${AWS_REGION:?}"
# Docker creates a missing ./secrets as root; `make up` creates it as the host user.
[ -w /secrets ] || fail "secrets/ is not writable by UID $(id -u) (secrets/rustfs/ on the RustFS variant): run 'sudo chown $(id -u) <directory>' on the host, then make up"
case ${S3_PATH_STYLE_ACCESS:-false} in true|false) ;; *) fail "S3_PATH_STYLE_ACCESS must be true or false" ;; esac

# field NAME: prints the string value of the JSON field NAME in $ANSWER.
field() { sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p" "$ANSWER"; }

# The retry covers a restart while Polaris is still booting.
curl -fsS --retry 30 --retry-all-errors --retry-delay 2 -o "$ANSWER" -X POST "$API/api/catalog/v1/oauth/tokens" \
  --user "$POLARIS_ROOT_CLIENT_ID:$POLARIS_ROOT_CLIENT_SECRET" \
  -d grant_type=client_credentials -d scope=PRINCIPAL_ROLE:ALL || fail "no root token"
token=$(field access_token)
[ -n "$token" ] || fail "no access_token in the token answer"

# call METHOD PATH BODY: prints the HTTP code; the answer goes to $ANSWER.
call() {
  curl -sS -o "$ANSWER" -w '%{http_code}' -X "$1" \
    -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
    "$MGMT$2" -d "$3"
}

# create WHAT METHOD PATH BODY: HTTP 2xx = created (set for PUT), 409 = already present.
create() {
  what=$1; shift
  verb=created; [ "$1" = PUT ] && verb=set
  code=$(call "$@")
  case $code in
    2??) echo "polaris-setup: $what $verb" ;;
    409) echo "polaris-setup: $what already present" ;;
    *) fail "$what: HTTP $code: $(cat "$ANSWER")" ;;
  esac
}

location="s3://$S3_BUCKET/polaris/"
# S3-compatible storage on-premise: endpoint and path-style access (not tested on AWS).
extra=""
if [ -n "${S3_ENDPOINT:-}" ]; then
  extra=",\"endpoint\":\"$S3_ENDPOINT\",\"pathStyleAccess\":${S3_PATH_STYLE_ACCESS:-false}"
  # S3-compatible storage such as RustFS rejects the KMS resources that Polaris adds to the session policy.
  extra="$extra,\"kmsUnavailable\":true"
fi
create "catalog lab_catalog" POST /catalogs "{\"catalog\":{\"name\":\"lab_catalog\",\"type\":\"INTERNAL\",\"readOnly\":false,\"properties\":{\"default-base-location\":\"$location\"},\"storageConfigInfo\":{\"storageType\":\"S3\",\"roleArn\":\"$POLARIS_ROLE_ARN\",\"externalId\":\"$POLARIS_EXTERNAL_ID\",\"region\":\"$AWS_REGION\",\"allowedLocations\":[\"$location\"]$extra}}}"

# ensure_principal NAME FILE PREFIX SERVICE: creates the principal NAME and writes its
# credentials to FILE as PREFIX_CLIENT_ID and PREFIX_CLIENT_SECRET. Polaris shows a secret only
# once: in the answer to the create call, or to a reset call. When NAME exists, FILE is kept
# if a token call with it works; else the credentials are reset and FILE is written again.
# SERVICE is the Compose service that reads FILE.
ensure_principal() {
  name=$1; out=$2; prefix=$3; service=$4
  code=$(call POST /principals "{\"principal\":{\"name\":\"$name\"}}")
  case $code in
    201) echo "polaris-setup: principal $name created"; write=1 ;;
    409)
      # The file is kept only if it works: a token call as NAME (nothing is printed).
      if [ -s "$out" ] && ( . "$out" && eval "id=\${${prefix}_CLIENT_ID:-}; secret=\${${prefix}_CLIENT_SECRET:-}" \
          && curl -fsS -o /dev/null -X POST "$API/api/catalog/v1/oauth/tokens" \
            --user "$id:$secret" -d grant_type=client_credentials -d scope=PRINCIPAL_ROLE:ALL ) >/dev/null 2>&1; then
        echo "polaris-setup: principal $name already present, credentials file kept"; write=0
      else
        reason="credentials file of $name does not work, credentials reset"
        [ -s "$out" ] || reason="principal $name already present, credentials reset"
        code=$(call POST "/principals/$name/reset" '{}')
        [ "$code" = 200 ] || fail "reset $name: HTTP $code"
        echo "polaris-setup: $reason"; write=1
      fi ;;
    *) fail "principal $name: HTTP $code: $(cat "$ANSWER")" ;;
  esac
  if [ "$write" = 1 ]; then
    id=$(field clientId)
    secret=$(field clientSecret)
    [ -n "$id" ] && [ -n "$secret" ] || fail "no clientId or clientSecret in the answer for $name"
    ( umask 077; printf '%s_CLIENT_ID=%s\n%s_CLIENT_SECRET=%s\n' "$prefix" "$id" "$prefix" "$secret" >"$out.new" )
    mv "$out.new" "$out"
    echo "polaris-setup: credentials written to secrets/${out##*/} (secrets/rustfs/ on the RustFS variant)"
    if [ "$code" = 200 ]; then
      echo "polaris-setup: credentials reset; run 'docker compose restart $service' if $service is already running"
    fi
  fi
}

ensure_principal spark_user /secrets/spark_user.env POLARIS_SPARK spark
# Created always, also when the profile trino is off: setup does not need to know the engines.
ensure_principal trino_user /secrets/trino_user.env POLARIS_TRINO trino

create "principal role spark_role" POST /principal-roles '{"principalRole":{"name":"spark_role"}}'
create "spark_role for spark_user" PUT /principals/spark_user/principal-roles '{"principalRole":{"name":"spark_role"}}'
create "catalog role lab_admin" POST /catalogs/lab_catalog/catalog-roles '{"catalogRole":{"name":"lab_admin"}}'
create "grant CATALOG_MANAGE_CONTENT" PUT /catalogs/lab_catalog/catalog-roles/lab_admin/grants '{"grant":{"type":"catalog","privilege":"CATALOG_MANAGE_CONTENT"}}'
create "lab_admin for spark_role" PUT /principal-roles/spark_role/catalog-roles/lab_catalog '{"catalogRole":{"name":"lab_admin"}}'
create "principal role trino_role" POST /principal-roles '{"principalRole":{"name":"trino_role"}}'
create "trino_role for trino_user" PUT /principals/trino_user/principal-roles '{"principalRole":{"name":"trino_role"}}'
create "lab_admin for trino_role" PUT /principal-roles/trino_role/catalog-roles/lab_catalog '{"catalogRole":{"name":"lab_admin"}}'

echo "polaris-setup: done"
