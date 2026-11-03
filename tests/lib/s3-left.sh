# s3_left CATALOG: prints the number of objects under the S3 prefix of CATALOG in a tpch_
# namespace. On a listing error (aws exit code above 1) prints the output and "left: aws s3
# ls failed" instead of a number. Source this file; do not run it.
s3_left() {
  local out rc=0
  out=$(docker compose exec -T spark bash -c "aws s3 ls --recursive s3://\$S3_BUCKET/$1/" 2>&1) || rc=$?
  if (( rc > 1 )); then echo "$out"; echo "left: aws s3 ls failed"; return; fi
  grep -c '/tpch_' <<<"$out" || true
}
