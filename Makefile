.PHONY: lint test-aws up down reset logs sql-nessie sql-polaris sql-rest sql-trino nessie-cli smoke-test tpch-gen tpch-load tpch-clean elt-require dbt elt-test

lint:
	tests/lint.sh
	tests/check-no-secrets.sh
	tests/compose-variant.sh

test-aws:
	tests/test-iam-policies.sh
	tests/test-aws-setup.sh
	tests/test-aws-teardown.sh

# Every profile, so that the catalogs that are off are also stopped or removed.
ALL_PROFILES = COMPOSE_PROFILES='*'

up:
	mkdir -p secrets secrets/rustfs landing
	@cfg=$$(docker compose config --format json) || exit 1; \
	dir=$$(printf '%s' "$$cfg" | jq -r '.services.rustfs.volumes[]? | select(.target == "/data") | .source') || exit 1; \
	if [ -n "$$dir" ]; then mkdir -p "$$dir"; fi
	@on=$$(docker compose config --services) || exit 1; \
	off=$$($(ALL_PROFILES) docker compose config --services | grep -vxF "$$on" || true); \
	if [ -n "$$off" ]; then $(ALL_PROFILES) docker compose stop $$off; fi
	docker compose up -d --build --wait --remove-orphans

down:
	$(ALL_PROFILES) docker compose down

reset:
	$(ALL_PROFILES) docker compose down -v

logs:
	docker compose logs -f --tail=200

sql-nessie:
	docker compose exec spark spark-sql --conf spark.sql.defaultCatalog=nessie

sql-polaris:
	docker compose exec spark spark-sql --conf spark.sql.defaultCatalog=polaris

sql-rest:
	docker compose exec spark spark-sql --conf spark.sql.defaultCatalog=rest

# Trino CLI (profile trino). Catalogs: nessie, polaris, rest (those that are on).
sql-trino:
	docker compose exec trino trino

nessie-cli:
	docker compose exec spark nessie

smoke-test:
	tests/smoke-test.sh

# ELT with dbt (spec 2026-10-30-dbt-elt). CATALOG = polaris, nessie or rest.
SF ?= 1

elt-require:
	elt/require.sh "$(CATALOG)"

tpch-gen:
	docker compose exec -T spark python3 /workspace/elt/tpch_gen.py "$(SF)" "/workspace/landing/tpch/sf$(SF)"

tpch-load: elt-require
	docker compose exec -T spark spark-submit /workspace/elt/tpch_load.py "$(CATALOG)" "$(SF)" "$(UNTIL)"

tpch-clean: elt-require
	docker compose exec -T spark spark-submit /workspace/elt/tpch_clean.py "$(CATALOG)"

# </dev/null: with an open stdin (a terminal), beeline waits for input and does not run -e (NOTES F8).
dbt:
	elt/require.sh "$(CATALOG)" thrift
	docker compose exec -T spark-thrift beeline -u 'jdbc:hive2://127.0.0.1:10000/;auth=noSasl' -n spark --silent=true -e "CREATE NAMESPACE IF NOT EXISTS $(CATALOG).default" </dev/null >/dev/null
	docker compose exec -T -w /workspace/dbt spark dbt $(ARGS) --target "$(CATALOG)"

elt-test:
	tests/elt.sh "$(CATALOG)"
