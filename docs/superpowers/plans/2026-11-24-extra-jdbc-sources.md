# Extra JDBC sources and SQL Server shipping source — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The lab Spark loads JDBC drivers and extra configuration from a local directory; a
small SQL Server shipping database, read by dbt-spark through a Spark JDBC catalog, serves dbt
study.

**Architecture:** Part L (lab, committed): `${LAB_EXTRA_DIR:-./local/spark}` is mounted at
`/opt/lab-extra` in `spark` and `spark-thrift`; `jars/` is on the driver class path and the
entrypoint appends `conf/*.conf`. Part S (local, never committed): SQL Server runs in its own
Compose project in the dbt project, published on the Docker bridge address; Spark reads it as
catalog `mssql`; dbt sources point to `mssql.dbo.*`.

**Tech Stack:** Docker Compose, bash, Spark 4.1.3 (`JDBCTableCatalog`), Microsoft JDBC driver
`mssql-jdbc` (jre11 build), SQL Server 2022 Developer, T-SQL, dbt-core 1.12.6 + dbt-spark 1.11.0
(thrift).

**Spec:** `docs/superpowers/specs/2026-11-24-extra-jdbc-sources-design.md`

---

## Conventions for every task

- Lab repository: `/home/admin/work/sramazzina/iceberg-platform-lab` (below: `LAB`). Branch
  `feat/extra-jdbc-sources` (exists, holds the spec and this plan; not pushed).
- dbt project: `/home/admin/work/academy/dbt-iceberg-lab` (below: `DBT`). Its `CLAUDE.md`
  names the lab `../iceberg-platform-poc`: that path is wrong (renamed, and not a sibling).
  Ignore it; use `LAB`. Do not fix it in this plan (spec section 2, out of scope).
- Part S files are never committed. In `DBT` they are excluded through `.git/info/exclude`.
  Before each task of Part S, `git -C DBT status --short` must not list them.
- Model routing (user rule): Sonnet subagents implement and review; the main agent (Opus)
  judges, writes the manual (Task 7) and talks to the user.
- Commits: no `Co-Authored-By`, no "Generated with" line.
- `NOTES.md` commits go directly to `main` (user rule). Code and README go through the PR.
- One catalog at a time (D20): during this plan `COMPOSE_PROFILES=nessie,thrift`.
- English in every file. Conversation with the user in Italian.

## File structure

Part L (lab, committed):

| File | Change | Responsibility |
|---|---|---|
| `.gitignore` | modify | ignore `/local/` |
| `.env.example` | modify | document `LAB_EXTRA_DIR` |
| `docker-compose.yml` | modify | mount and `extra_hosts` in `spark`, `spark-thrift` |
| `spark/conf/spark-defaults.conf` | modify | driver class path |
| `spark/entrypoint.sh` | modify | append `conf/*.conf` |
| `Makefile` | modify | `up` creates the extra directory |
| `tests/extra-dir.sh` | create | test of the mechanism |
| `README.md` | modify | section "Local files and extra JDBC sources" |
| `NOTES.md` (on `main`) | modify | D21, F12 |

Part S (local):

| File | Responsibility |
|---|---|
| `DBT/sqlserver-source/compose.yaml` | SQL Server container |
| `DBT/sqlserver-source/.env` | passwords |
| `DBT/sqlserver-source/run.sh` | `up`, `init`, `reset`, `advance`, `status`, `down` |
| `DBT/sqlserver-source/sql/01_schema.sql` | database, tables, `sim_clock` |
| `DBT/sqlserver-source/sql/02_seed.sql` | initial data with defects |
| `DBT/sqlserver-source/sql/03_reader.sql` | login `dbt_reader` |
| `DBT/sqlserver-source/sql/advance_time.sql` | one simulated day |
| `DBT/sqlserver-source/MANUAL.html` | manual |
| `DBT/models/shipping/_sources.yml` | dbt source `shipping` |
| `DBT/models/shipping/shipping_smoke.sql` | smoke model |
| `LAB/local/spark/jars/mssql-jdbc-<version>.jre11.jar` | driver |
| `LAB/local/spark/conf/mssql.conf` | catalog `mssql` |

## Expected row counts (used by Tasks 5, 6, 7)

| State | customers | shipments | parcels | tracking_events | delivered (`LOWER(status)`) |
|---|---|---|---|---|---|
| after `init` (day 0) | 15 | 30 | 43 | 91 | 6 |
| after 1 `advance` (day 1) | 15 | 32 | 46 | 117 | 12 |
| after 2 `advance` (day 2) | 15 | 34 | 49 | 139 | 18 |
| after 3 `advance` (day 3) | 15 | 36 | 52 | 158 | 24 |

Derivation (check it if a count differs, before changing a script):

- Shipment `n` (1..30) has `k = 1 + n % 5` events (steps 1..k): sum = 90; plus 1 duplicate = 91.
- Delivered at day 0: `k = 5`, i.e. `n % 5 = 4`: n = 4, 9, 14, 19, 24, 29.
- Parcels: `1 + n % 2` per shipment = 45; shipment 13 has none (−2) = 43.
- Each `advance`: every open shipment gets one event and moves one step; then 2 new shipments
  (1 event each; parcels `1 + id % 2`, i.e. 2 + 1 = 3). Day 1: 24 open → +24 + 2 = 117; the 6
  shipments at step 4 become delivered. Day 2: 20 open → +20 + 2 = 139; 6 more delivered. Day 3:
  open = 34 − 18 = 16 → 139 + 16 + 2 + 1 late event = 158; delivered: the 6 shipments that were at
  step 2 on day 0 (n % 5 = 1) reach step 5 → 24.

---

### Task 0: Issues

**Files:** none.

- [ ] **Step 1: Create the main issue**

```bash
cd LAB
gh issue create --title "Extra JDBC sources for the lab Spark (local drivers and configuration)" \
  --label enhancement --label "area: spark" --body "$(cat <<'EOF'
Spec: `docs/superpowers/specs/2026-11-24-extra-jdbc-sources-design.md`
Plan: `docs/superpowers/plans/2026-11-24-extra-jdbc-sources.md`

The lab Spark loads JDBC drivers and extra configuration from a local, git-ignored directory
(`LAB_EXTRA_DIR`, default `./local/spark`). First use: a local SQL Server shipping source for
dbt study (local files, not committed; evidence in comments here).

- [ ] Task 1: mount, class path, entrypoint, Makefile, test
- [ ] Task 2: README, regression on nessie, D21
- [ ] Task 3: SQL Server container and schema (local)
- [ ] Task 4: spike, dbt-spark sources on catalog mssql (gate)
- [ ] Task 5: seed data, simulated time (local)
- [ ] Task 6: dbt source and smoke model, end to end (local)
- [ ] Task 7: manual (local)
- [ ] Task 8: PR, F12, handoff
EOF
)"
```

Expected: the issue URL. Record the number as `#N` and replace "to be opened" in the spec
header with `#N` (commit `docs(spec): link issue #N`).

---

### Task 1: Lab mechanism (mount, class path, entrypoint, Makefile)

**Files:**
- Create: `tests/extra-dir.sh`
- Modify: `docker-compose.yml` (services `spark` and `spark-thrift`), `spark/conf/spark-defaults.conf`,
  `spark/entrypoint.sh`, `Makefile` (target `up`), `.gitignore`, `.env.example`

- [ ] **Step 1: Check the container user**

Run: `cd LAB && docker compose run --rm --no-deps -T spark id`
Expected: a uid that is not 1000 (the `spark` user of the image). Record it for the README
(Task 2): files in the extra directory must be readable by that uid.

- [ ] **Step 2: Write the failing test** — `tests/extra-dir.sh` (mode 755)

```bash
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
  spark-sql -e 'SET spark.lab.extra.probe' 2>/dev/null | tail -1 || echo "spark-sql failed")
assert_contains "$val" "ok" "spark-sql sees the appended property"

hosts=$(docker compose run --rm --no-deps -T spark getent hosts host.docker.internal 2>/dev/null || echo "none")
assert_contains "$hosts" "host.docker.internal" "host.docker.internal resolves in the container"

finish
```

- [ ] **Step 3: Run the test; it must fail**

Run: `tests/extra-dir.sh`
Expected: FAIL lines for the mount, `extra_hosts`, the appended file and the class path.

- [ ] **Step 4: Compose** — in `docker-compose.yml`, service `spark`, append to `volumes:`, and
  add `extra_hosts:` after `volumes:`; do the same in service `spark-thrift`:

```yaml
      # Extra JDBC sources (spec 2026-11-24-extra-jdbc-sources): driver jars in jars/,
      # Spark configuration files in conf/. Local, git-ignored.
      - ${LAB_EXTRA_DIR:-./local/spark}:/opt/lab-extra:ro
    extra_hosts:
      # Sources that run on the host or in another Compose project.
      - host.docker.internal:host-gateway
```

- [ ] **Step 5: Class path** — append to `spark/conf/spark-defaults.conf`:

```
# Extra JDBC drivers (spec 2026-11-24-extra-jdbc-sources). Local mode: the driver JVM is the
# only JVM. An empty directory has no effect.
spark.driver.extraClassPath    /opt/lab-extra/jars/*
```

- [ ] **Step 6: Entrypoint** — in `spark/entrypoint.sh`, inside the `{ ... } >"$conf.new"`
  block, after the `for catalog` loop, before the closing `}`:

```bash
  # Extra configuration (spec 2026-11-24-extra-jdbc-sources): local files mounted from
  # LAB_EXTRA_DIR, appended as is, in lexical order. A file that cannot be read stops the start.
  for extra in /opt/lab-extra/conf/*.conf; do
    [[ -f $extra ]] || continue
    printf '\n# %s (LAB_EXTRA_DIR)\n' "${extra##*/}"
    cat "$extra"
  done
```

Also update the header comment of the file: "Renders the Spark configuration for the catalogs
that are on (...) and appends the extra configuration files of LAB_EXTRA_DIR, then starts
JupyterLab."

- [ ] **Step 7: Makefile** — in target `up`, after the RustFS data directory block, add:

```make
	@cfg=$$(docker compose config --format json) || exit 1; \
	dir=$$(printf '%s' "$$cfg" | jq -r '.services.spark.volumes[]? | select(.target == "/opt/lab-extra") | .source') || exit 1; \
	if [ -n "$$dir" ]; then mkdir -p "$$dir/jars" "$$dir/conf"; fi
```

- [ ] **Step 8: `.gitignore` and `.env.example`**

`.gitignore`, new line: `/local/`

`.env.example`, new block after "Catalogs":

```
# ---- Extra JDBC sources -------------------------------------------------------
# Host directory with jars/ (JDBC drivers) and conf/ (*.conf Spark settings, for example a
# JDBCTableCatalog). Mounted read-only in spark and spark-thrift. `make up` creates it.
# Default: ./local/spark (git-ignored). See README "Local files and extra JDBC sources".
#LAB_EXTRA_DIR=./local/spark
```

- [ ] **Step 9: Rebuild and run the test; it must pass**

Run: `make up && tests/extra-dir.sh`
Expected: all `ok`, exit 0. `ls -ld local/spark/jars local/spark/conf` shows two directories
owned by the host user.

- [ ] **Step 10: Run the existing configuration tests**

Run: `make lint && tests/spark-config.sh`
Expected: `lint passed`; all `ok`.

- [ ] **Step 11: Commit**

```bash
git add .gitignore .env.example docker-compose.yml spark/conf/spark-defaults.conf spark/entrypoint.sh Makefile tests/extra-dir.sh
git commit -m "feat(spark): load JDBC drivers and extra configuration from LAB_EXTRA_DIR (#N)"
```

---

### Task 2: README, regression on nessie, D21

**Files:** Modify `README.md`; `NOTES.md` on `main`.

- [ ] **Step 1: README section** — new section `## Local files and extra JDBC sources`, before
  `## On-premise with RustFS`. Content (ASD-STE100 style, like the other sections):

1. `local/` is git-ignored; use it for installation-specific files.
2. `LAB_EXTRA_DIR` (default `./local/spark`): `jars/` for JDBC driver jars, `conf/` for
   `*.conf` files with Spark settings. Mounted read-only in `spark` and `spark-thrift`.
3. Permissions: the container user (uid from Task 1 Step 1) reads the files. Keep `local/`
   mode 700 on the host; give `local/spark`, `jars/`, `conf/` mode 755 and the files mode 644.
   Docker resolves the bind mount as root, so the mode of `local/` does not block the
   container.
4. Example: SQL Server. The driver jar from Maven Central (`com.microsoft.sqlserver:mssql-jdbc`,
   `jre11` build), and `conf/mssql.conf`:

```
spark.sql.catalog.mssql           org.apache.spark.sql.execution.datasources.v2.jdbc.JDBCTableCatalog
spark.sql.catalog.mssql.url       jdbc:sqlserver://host.docker.internal:1433;databaseName=<db>;encrypt=true;trustServerCertificate=true
spark.sql.catalog.mssql.user      <read-only login>
spark.sql.catalog.mssql.password  <password>
```

5. `host.docker.internal` is the host. A source in another Compose project must publish its
   port on the Docker bridge address (`172.17.0.1`), not on `127.0.0.1`.
6. After a change: `docker compose restart spark spark-thrift`.
7. A catalog from `conf/` is a read-only source, not an Iceberg catalog: the rule "one catalog
   at a time" (NOTES D20) does not count it.
8. Troubleshooting: `No suitable driver` (jar missing); `Permission denied` at start (file mode);
   connection refused (port published on `127.0.0.1`).

Also add `tests/extra-dir.sh` to the test list of the README if the README lists tests.

- [ ] **Step 2: Regression on nessie**

Run, with `COMPOSE_PROFILES=nessie,thrift` and an empty `local/spark`:

```bash
make lint && tests/spark-config.sh && tests/extra-dir.sh && make smoke-test && tests/thrift-service.sh
```

Expected: every script ends with all `ok`. Paste the summary in a comment of issue `#N`.

- [ ] **Step 3: Commit the README**

```bash
git add README.md
git commit -m "docs(readme): document local files and extra JDBC sources (#N)"
```

- [ ] **Step 4: D21 on `main`** — after the commit of Step 3 (clean tree):
  `git switch main && git pull`, then add to `NOTES.md` after D20:

```markdown
### D21 — Extra JDBC sources are not Iceberg catalogs (2026-11-24, #N)

A Spark catalog added through `LAB_EXTRA_DIR/conf/` (for example a `JDBCTableCatalog` on SQL
Server) is a read-only source. The rule "one catalog at a time" (D20) counts only the Iceberg
catalogs (nessie, polaris, rest). Spec `2026-11-24-extra-jdbc-sources-design.md`.
```

`git commit -m "docs(notes): record decision D21, extra JDBC sources (#N)"`, `git push`,
`git switch feat/extra-jdbc-sources`.

---

### Task 3: SQL Server container and schema (Part S)

**Files:** create in `DBT/sqlserver-source/`: `compose.yaml`, `.env`, `run.sh`,
`sql/01_schema.sql`, `sql/03_reader.sql`.

- [ ] **Step 1: Exclude Part S from git in the dbt project**

```bash
printf '/sqlserver-source/\n/models/shipping/\n' >> /home/admin/work/academy/dbt-iceberg-lab/.git/info/exclude
```

- [ ] **Step 2: Check the disk and the bridge address**

Run: `df -h / | tail -1; ip -4 addr show docker0 | grep inet`
Expected: more than 3 GB free (else stop and ask the user about `docker builder prune`);
`inet 172.17.0.1/16`.

- [ ] **Step 3: Pin the image tag**

```bash
curl -fsS https://mcr.microsoft.com/v2/mssql/server/tags/list | jq -r '.tags[]' \
  | grep -E '^2022-CU[0-9]+-ubuntu-22\.04$' | sort -V | tail -1
```

Expected: one tag, for example `2022-CU21-ubuntu-22.04`. Use it as `<TAG>` below.

- [ ] **Step 4: `.env`** (mode 600). Passwords: at least 10 characters, upper case, lower case,
  digit, symbol (SQL Server policy). Generate them; do not print them.

```bash
cd /home/admin/work/academy/dbt-iceberg-lab/sqlserver-source
umask 077
printf 'MSSQL_SA_PASSWORD=Sa1!%s\nMSSQL_READER_PASSWORD=Rd1!%s\n' \
  "$(openssl rand -hex 12)" "$(openssl rand -hex 12)" > .env
```

- [ ] **Step 5: `compose.yaml`**

```yaml
# Local SQL Server shipping source for dbt study (spec 2026-11-24-extra-jdbc-sources, 5.1).
# Not part of the lab: the lab reaches it at host.docker.internal:1433.
name: shipping-source
services:
  sqlserver:
    image: mcr.microsoft.com/mssql/server:<TAG>
    environment:
      ACCEPT_EULA: "Y"
      MSSQL_PID: Developer
      MSSQL_MEMORY_LIMIT_MB: "2048"
      MSSQL_SA_PASSWORD: ${MSSQL_SA_PASSWORD:?set it in .env}
      MSSQL_READER_PASSWORD: ${MSSQL_READER_PASSWORD:?set it in .env}
    ports:
      # Docker bridge address: reachable from the host and the lab containers, not from outside.
      - "172.17.0.1:1433:1433"
    volumes:
      - mssql-data:/var/opt/mssql
      - ./sql:/sql:ro
    healthcheck:
      test: ["CMD-SHELL", "/opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P \"$$MSSQL_SA_PASSWORD\" -Q 'SELECT 1' -b -o /dev/null"]
      interval: 5s
      timeout: 5s
      retries: 30
      start_period: 20s
volumes:
  mssql-data:
```

- [ ] **Step 6: `sql/01_schema.sql`** (drops and creates; `reset` runs it again)

```sql
-- Shipping source: database, tables, simulated clock (spec 2026-11-24, 5.3).
IF DB_ID(N'shipping') IS NOT NULL
BEGIN
  ALTER DATABASE shipping SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
  DROP DATABASE shipping;
END
GO
CREATE DATABASE shipping;
GO
USE shipping;
GO
CREATE TABLE dbo.customers (
  customer_id    INT IDENTITY(1,1) PRIMARY KEY,
  customer_name  NVARCHAR(100) NOT NULL,
  email          NVARCHAR(200) NULL,
  country_code   NVARCHAR(5)   NOT NULL,
  created_at     DATETIME2(0)  NOT NULL,
  updated_at     DATETIME2(0)  NOT NULL
);
CREATE TABLE dbo.shipments (
  shipment_id       INT IDENTITY(1,1) PRIMARY KEY,
  customer_id       INT           NOT NULL REFERENCES dbo.customers (customer_id),
  origin_city       NVARCHAR(60)  NOT NULL,
  destination_city  NVARCHAR(60)  NOT NULL,
  service_level     NVARCHAR(20)  NOT NULL,
  status            NVARCHAR(20)  NOT NULL,
  promised_date     DATE          NOT NULL,
  created_at        DATETIME2(0)  NOT NULL,
  updated_at        DATETIME2(0)  NOT NULL
);
CREATE TABLE dbo.parcels (
  parcel_id    INT IDENTITY(1,1) PRIMARY KEY,
  shipment_id  INT           NOT NULL REFERENCES dbo.shipments (shipment_id),
  weight_kg    DECIMAL(8,2)  NOT NULL,
  length_cm    INT           NOT NULL,
  width_cm     INT           NOT NULL,
  height_cm    INT           NOT NULL,
  created_at   DATETIME2(0)  NOT NULL
);
CREATE TABLE dbo.tracking_events (
  event_id     INT IDENTITY(1,1) PRIMARY KEY,
  shipment_id  INT           NOT NULL REFERENCES dbo.shipments (shipment_id),
  event_type   NVARCHAR(30)  NOT NULL,
  event_time   DATETIME2(0)  NOT NULL,
  location     NVARCHAR(80)  NOT NULL,
  loaded_at    DATETIME2(0)  NOT NULL
);
CREATE TABLE dbo.sim_clock (
  id        TINYINT PRIMARY KEY CHECK (id = 1),
  sim_day   INT  NOT NULL,
  sim_date  DATE NOT NULL
);
INSERT INTO dbo.sim_clock (id, sim_day, sim_date) VALUES (1, 0, '2026-03-01');
GO
```

- [ ] **Step 7: `sql/03_reader.sql`**

```sql
-- Read-only login for Spark (spec 2026-11-24, 5.2). Password from sqlcmd -v READER_PASSWORD.
IF SUSER_ID(N'dbt_reader') IS NULL
  CREATE LOGIN dbt_reader WITH PASSWORD = N'$(READER_PASSWORD)', CHECK_POLICY = OFF;
ELSE
  ALTER LOGIN dbt_reader WITH PASSWORD = N'$(READER_PASSWORD)';
GO
USE shipping;
GO
CREATE USER dbt_reader FOR LOGIN dbt_reader;
ALTER ROLE db_datareader ADD MEMBER dbt_reader;
GO
```

- [ ] **Step 8: `run.sh`** (mode 755)

```bash
#!/usr/bin/env bash
# Local SQL Server shipping source (spec 2026-11-24-extra-jdbc-sources, 5.5).
# Usage: run.sh up | init | reset | advance | status | down
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

# sql FILE: runs /sql/FILE as sa inside the container; stops on the first error.
sql() {
  docker compose exec -T sqlserver bash -c \
    '/opt/mssql-tools18/bin/sqlcmd -C -b -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -v READER_PASSWORD="$MSSQL_READER_PASSWORD" -i "$1"' \
    _ "/sql/$1"
}

# query SQL: runs one statement as sa; prints rows without header.
query() {
  docker compose exec -T sqlserver bash -c \
    '/opt/mssql-tools18/bin/sqlcmd -C -b -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -d shipping -h -1 -W -s "|" -Q "SET NOCOUNT ON; $1"' \
    _ "$1"
}

init() {
  for f in 01_schema.sql 02_seed.sql 03_reader.sql; do
    if [[ -f sql/$f ]]; then echo "run $f"; sql "$f"; fi
  done
}

case "${1:-}" in
  up) docker compose up -d --wait ;;
  init | reset) init ;;
  advance) sql advance_time.sql ;;
  status)
    query "SELECT 'day', CAST(sim_day AS varchar(10)) + ' ' + CONVERT(varchar(10), sim_date, 23) FROM dbo.sim_clock
           UNION ALL SELECT 'customers', CAST(COUNT(*) AS varchar(10)) FROM dbo.customers
           UNION ALL SELECT 'shipments', CAST(COUNT(*) AS varchar(10)) FROM dbo.shipments
           UNION ALL SELECT 'parcels', CAST(COUNT(*) AS varchar(10)) FROM dbo.parcels
           UNION ALL SELECT 'tracking_events', CAST(COUNT(*) AS varchar(10)) FROM dbo.tracking_events
           UNION ALL SELECT 'delivered', CAST(COUNT(*) AS varchar(10)) FROM dbo.shipments WHERE LOWER(status) = 'delivered'" ;;
  down) docker compose down ;;
  *) echo "usage: $0 up | init | reset | advance | status | down" >&2; exit 2 ;;
esac
```

- [ ] **Step 9: Start and initialise**

Run: `./run.sh up && ./run.sh init && ./run.sh status`
Expected: container healthy; `run 01_schema.sql`, `run 03_reader.sql`; status shows
`day|0 2026-03-01` and 0 for each table.

- [ ] **Step 10: Check the read-only login**

```bash
docker compose exec -T sqlserver bash -c '/opt/mssql-tools18/bin/sqlcmd -C -b -S localhost -U dbt_reader -P "$MSSQL_READER_PASSWORD" -d shipping -Q "SELECT COUNT(*) FROM dbo.customers"'
docker compose exec -T sqlserver bash -c '/opt/mssql-tools18/bin/sqlcmd -C -b -S localhost -U dbt_reader -P "$MSSQL_READER_PASSWORD" -d shipping -Q "INSERT INTO dbo.sim_clock VALUES (2, 0, GETDATE())"' ; echo "exit=$?"
```

Expected: first command prints `0`; second fails with a permission error and `exit=1`.

- [ ] **Step 11: Check the port binding**

Run: `docker compose port sqlserver 1433; git -C /home/admin/work/academy/dbt-iceberg-lab status --short`
Expected: `172.17.0.1:1433`; git status empty.

No commit (Part S). Comment on issue `#N`: image tag, status output, results of Steps 10-11.

---

### Task 4: Spike — Spark JDBC catalog and dbt-spark sources (gate)

**Files:** create `LAB/local/spark/jars/mssql-jdbc-<version>.jre11.jar`,
`LAB/local/spark/conf/mssql.conf`; temporary `DBT/models/shipping/_sources.yml`.

- [ ] **Step 1: Download the driver with checksum**

```bash
cd LAB/local/spark/jars
base=https://repo1.maven.org/maven2/com/microsoft/sqlserver/mssql-jdbc
v=$(curl -fsS "$base/maven-metadata.xml" | grep -oE '<version>[0-9.]+\.jre11</version>' | sed -E 's/<\/?version>//g' | sort -V | tail -1)
curl -fsSLO "$base/$v/mssql-jdbc-$v.jar"
echo "$(curl -fsS "$base/$v/mssql-jdbc-$v.jar.sha1")  mssql-jdbc-$v.jar" | sha1sum -c -
chmod 644 "mssql-jdbc-$v.jar"; echo "$v"
```

Expected: `mssql-jdbc-<v>.jar: OK` and the version. Record it.

- [ ] **Step 2: `conf/mssql.conf`** (mode 644; see README permissions)

```bash
cd LAB/local/spark/conf
pw=$(grep '^MSSQL_READER_PASSWORD=' /home/admin/work/academy/dbt-iceberg-lab/sqlserver-source/.env | cut -d= -f2-)
cat > mssql.conf <<EOF
# Catalog mssql: local SQL Server shipping source (spec 2026-11-24-extra-jdbc-sources, 5.8).
spark.sql.catalog.mssql           org.apache.spark.sql.execution.datasources.v2.jdbc.JDBCTableCatalog
spark.sql.catalog.mssql.url       jdbc:sqlserver://host.docker.internal:1433;databaseName=shipping;encrypt=true;trustServerCertificate=true
spark.sql.catalog.mssql.user      dbt_reader
spark.sql.catalog.mssql.password  $pw
EOF
chmod 644 mssql.conf
```

- [ ] **Step 3: Restart and query with Spark (spec 6.1)**

```bash
cd LAB && docker compose restart spark spark-thrift && docker compose up -d --wait
docker compose exec -T spark-thrift beeline -u 'jdbc:hive2://127.0.0.1:10000/;auth=noSasl' -n spark --silent=true \
  -e "SHOW NAMESPACES IN mssql; SHOW TABLES IN mssql.dbo; DESCRIBE mssql.dbo.shipments; DESCRIBE mssql.dbo.tracking_events; DESCRIBE mssql.dbo.parcels; SELECT COUNT(*) FROM mssql.dbo.customers WHERE country_code = 'IT'" </dev/null
```

Expected: namespace `dbo`; the 5 tables; column types; count `0` (no seed yet). Record the type
mapping of `INT`, `NVARCHAR`, `DATETIME2(0)`, `DATE`, `DECIMAL(8,2)`, `TINYINT` (spec 6.3).
If it fails: stop and report the error (driver, permissions, network).

- [ ] **Step 4: Thrift start with SQL Server down (spec 6.3)**

```bash
(cd /home/admin/work/academy/dbt-iceberg-lab/sqlserver-source && docker compose stop)
cd LAB && docker compose restart spark-thrift && docker compose up -d --wait spark-thrift
docker compose exec -T spark-thrift beeline -u 'jdbc:hive2://127.0.0.1:10000/;auth=noSasl' -n spark --silent=true -e "SELECT 42; SHOW TABLES IN mssql.dbo" </dev/null
(cd /home/admin/work/academy/dbt-iceberg-lab/sqlserver-source && ./run.sh up)
```

Expected: `spark-thrift` healthy; `42`; the second statement fails with a connection error.
If `spark-thrift` does not start: stop and report (spec 8 is then wrong).

- [ ] **Step 5: dbt environment**

```bash
cd /home/admin/work/academy/dbt-iceberg-lab
py=$(ls -d ~/.local/share/uv/python/cpython-3.11-*/bin/python3.11 | head -1)
uv venv --python "$py" .venv && . .venv/bin/activate && uv pip install -r requirements.txt && pip check
unset DBT_PROFILES_DIR; dbt debug --profiles-dir .
```

Expected: `All checks passed!`.

- [ ] **Step 6: Try a, b, c in order (spec 6.2); stop at the first that works**

For each variant, write `models/shipping/_sources.yml`, then run
`dbt compile --profiles-dir . --inline "select count(*) from {{ source('shipping', 'customers') }}"`
and `dbt show --profiles-dir . --inline "select count(*) as n from {{ source('shipping', 'customers') }}"`.

Variant a:

```yaml
version: 2
sources:
  - name: shipping
    database: mssql
    schema: dbo
    tables: [{name: customers}]
```

Variant b:

```yaml
version: 2
sources:
  - name: shipping
    schema: mssql.dbo
    quoting: {database: false, schema: false, identifier: false}
    tables: [{name: customers}]
```

Variant c: a project macro that overrides `source()` for the source `shipping` only. dbt
reads macros only from the `macro-paths` of the project (`macros/`), so the file is
`DBT/macros/source_catalog.sql`; add `/macros/source_catalog.sql` to `.git/info/exclude`
first. The `_sources.yml` is the one of variant a without `database:` (`schema: dbo`).

```sql
{% macro source(source_name, table_name) %}
  {%- set rel = builtins.source(source_name, table_name) -%}
  {%- if source_name == 'shipping' -%}
    {{ return(api.Relation.create(schema='mssql.dbo', identifier=table_name, quote_policy={'schema': false, 'identifier': false})) }}
  {%- else -%}
    {{ return(rel) }}
  {%- endif -%}
{% endmacro %}
```

Expected: compiled SQL `select count(*) from mssql.dbo.customers`, and `dbt show` returns `0`.
Record which variant works and the exact error of each variant that fails.

If a, b and c fail: **stop**. Report to the user; the fallback (spec B9) needs their decision.

- [ ] **Step 7: F12 on `main`** — `NOTES.md`, after F10 (F11 is reserved for #70):

```markdown
### F12 — dbt-spark sources on a Spark JDBC catalog (checked 2026-11-<dd>, #N)

<variant that works, with the YAML>; <errors of the variants that fail>. Type mapping SQL
Server → Spark: <table from Step 3>. `spark-thrift` starts when the JDBC source is down;
only queries on the catalog fail (<error text>). Driver mssql-jdbc <v>, SQL Server <TAG>.
```

Fill every `<...>` with the recorded results before the commit. Commit on `main`
(`docs(notes): record finding F12, dbt-spark sources on a JDBC catalog (#N)`), push, switch
back to the branch. Comment on issue `#N` with the same content.

---

### Task 5: Seed data and simulated time (Part S)

**Files:** create `DBT/sqlserver-source/sql/02_seed.sql`, `DBT/sqlserver-source/sql/advance_time.sql`.

- [ ] **Step 1: `sql/02_seed.sql`**

```sql
-- Initial data with intended defects (spec 2026-11-24, 5.3-5.4). Deterministic.
USE shipping;
SET NOCOUNT ON;
DECLARE @base DATETIME2(0) = '2026-03-01T00:00:00';
DECLARE @steps TABLE (step INT PRIMARY KEY, event_type NVARCHAR(30));
INSERT INTO @steps VALUES (1, N'picked_up'), (2, N'in_transit'), (3, N'at_depot'),
                          (4, N'out_for_delivery'), (5, N'delivered');
DECLARE @cities TABLE (i INT PRIMARY KEY, city NVARCHAR(60));
INSERT INTO @cities VALUES (0, N'Milano'), (1, N'Roma'), (2, N'Torino'), (3, N'Napoli'),
                           (4, N'Bologna'), (5, N'Firenze');

-- Customers. Defects: id 7 email NULL; id 11 country code with trailing spaces.
INSERT INTO dbo.customers (customer_name, email, country_code, created_at, updated_at) VALUES
 (N'Alpha Logistics',   N'ops@alpha.example',   N'IT',   '2026-01-17', '2026-01-17'),
 (N'Beta Retail',       N'ship@beta.example',   N'IT',   '2026-01-18', '2026-01-18'),
 (N'Gamma Foods',       N'log@gamma.example',   N'FR',   '2026-01-19', '2026-01-19'),
 (N'Delta Tools',       N'ops@delta.example',   N'DE',   '2026-01-20', '2026-01-20'),
 (N'Epsilon Books',     N'info@epsilon.example',N'IT',   '2026-01-21', '2026-01-21'),
 (N'Zeta Garden',       N'zeta@zeta.example',   N'ES',   '2026-01-22', '2026-01-22'),
 (N'Eta Pharma',        NULL,                   N'CH',   '2026-01-23', '2026-01-23'),
 (N'Theta Fashion',     N'ops@theta.example',   N'IT',   '2026-01-24', '2026-01-24'),
 (N'Iota Electronics',  N'iota@iota.example',   N'DE',   '2026-01-25', '2026-01-25'),
 (N'Kappa Sports',      N'ship@kappa.example',  N'FR',   '2026-01-26', '2026-01-26'),
 (N'Lambda Home',       N'home@lambda.example', N'IT  ', '2026-01-27', '2026-01-27'),
 (N'Mu Toys',           N'mu@mu.example',       N'ES',   '2026-01-28', '2026-01-28'),
 (N'Nu Wines',          N'cellar@nu.example',   N'IT',   '2026-01-29', '2026-01-29'),
 (N'Xi Office',         N'xi@xi.example',       N'CH',   '2026-01-30', '2026-01-30'),
 (N'Omicron Bikes',     N'ride@omicron.example',N'IT',   '2026-01-31', '2026-01-31');

-- Shipments 1..30: k = 1 + n % 5 steps done. Defect: status spelling for n = 9 and 19.
SET IDENTITY_INSERT dbo.shipments ON;
WITH nums AS (SELECT TOP (30) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects),
     s AS (SELECT n, 1 + n % 5 AS k, DATEADD(hour, 9, DATEADD(day, -(31 - n), @base)) AS created_at FROM nums)
INSERT INTO dbo.shipments (shipment_id, customer_id, origin_city, destination_city, service_level,
                           status, promised_date, created_at, updated_at)
SELECT s.n, (s.n - 1) % 15 + 1, o.city, d.city,
       CASE WHEN s.n % 3 = 0 THEN N'express' ELSE N'standard' END,
       CASE WHEN s.n = 9 THEN N'DELIVERED' WHEN s.n = 19 THEN N'Delivered' ELSE st.event_type END,
       CAST(DATEADD(day, CASE WHEN s.n % 3 = 0 THEN 2 ELSE 5 END, s.created_at) AS DATE),
       s.created_at, DATEADD(hour, 1 + 6 * (s.k - 1), s.created_at)
FROM s
JOIN @cities o ON o.i = s.n % 6
JOIN @cities d ON d.i = (s.n + 2) % 6
JOIN @steps st ON st.step = s.k;
SET IDENTITY_INSERT dbo.shipments OFF;

-- Tracking events: steps 1..k per shipment.
INSERT INTO dbo.tracking_events (shipment_id, event_type, event_time, location, loaded_at)
SELECT sh.shipment_id, st.event_type,
       DATEADD(hour, 1 + 6 * (st.step - 1), sh.created_at),
       CASE st.step WHEN 1 THEN sh.origin_city WHEN 5 THEN sh.destination_city
                    ELSE N'Depot ' + sh.destination_city END,
       DATEADD(minute, 10, DATEADD(hour, 1 + 6 * (st.step - 1), sh.created_at))
FROM dbo.shipments sh
JOIN @steps st ON st.step <= 1 + sh.shipment_id % 5
ORDER BY sh.shipment_id, st.step;

-- Defect: duplicated event (same shipment, type, time; new event_id).
INSERT INTO dbo.tracking_events (shipment_id, event_type, event_time, location, loaded_at)
SELECT shipment_id, event_type, event_time, location, loaded_at
FROM dbo.tracking_events WHERE shipment_id = 2 AND event_type = N'in_transit';

-- Parcels: 1 + n % 2 per shipment. Defects: shipment 13 has none; first parcel of 21 weighs 0.
INSERT INTO dbo.parcels (shipment_id, weight_kg, length_cm, width_cm, height_cm, created_at)
SELECT sh.shipment_id,
       CASE WHEN sh.shipment_id = 21 AND x.seq = 1 THEN 0
            ELSE CAST(0.50 + ((sh.shipment_id * 7 + x.seq * 3) % 20) * 0.75 AS DECIMAL(8,2)) END,
       20 + (sh.shipment_id * 3) % 40, 15 + (sh.shipment_id * 5) % 25, 10 + x.seq * 4,
       sh.created_at
FROM dbo.shipments sh
JOIN (VALUES (1), (2)) AS x(seq) ON x.seq <= 1 + sh.shipment_id % 2
WHERE sh.shipment_id <> 13
ORDER BY sh.shipment_id, x.seq;
GO
```

- [ ] **Step 2: Run init and check day 0**

Run: `./run.sh reset && ./run.sh status`
Expected (table "Expected row counts"): `day|0 2026-03-01`, customers 15, shipments 30,
parcels 43, tracking_events 91, delivered 6.

- [ ] **Step 3: Check the defects**

```bash
docker compose exec -T sqlserver bash -c '/opt/mssql-tools18/bin/sqlcmd -C -b -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -d shipping -h -1 -W -Q "SET NOCOUNT ON;
SELECT COUNT(*) FROM dbo.customers WHERE email IS NULL;
SELECT COUNT(*) FROM dbo.customers WHERE country_code <> RTRIM(country_code);
SELECT DISTINCT status FROM dbo.shipments WHERE LOWER(status) = N'"'"'delivered'"'"';
SELECT COUNT(*) FROM dbo.shipments s WHERE NOT EXISTS (SELECT 1 FROM dbo.parcels p WHERE p.shipment_id = s.shipment_id);
SELECT COUNT(*) FROM dbo.parcels WHERE weight_kg = 0;
SELECT COUNT(*) FROM (SELECT shipment_id, event_type, event_time FROM dbo.tracking_events GROUP BY shipment_id, event_type, event_time HAVING COUNT(*) > 1) d;"'
```

Expected: `1`, `1`, three spellings (`DELIVERED`, `Delivered`, `delivered`), `1`, `1`, `1`.
(`SQL_Latin1_General_CP1_CI_AS` is case-insensitive: `DISTINCT` can return one spelling. If
so, use `SELECT DISTINCT status COLLATE Latin1_General_CS_AS` and record it for the manual.)

- [ ] **Step 4: `sql/advance_time.sql`**

```sql
-- One simulated day (spec 2026-11-24, 5.5). Deterministic: rows are chosen from the day number.
USE shipping;
SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRANSACTION;

UPDATE dbo.sim_clock SET sim_day = sim_day + 1, sim_date = DATEADD(day, 1, sim_date) WHERE id = 1;
DECLARE @d INT, @date DATE;
SELECT @d = sim_day, @date = sim_date FROM dbo.sim_clock WHERE id = 1;
DECLARE @day DATETIME2(0) = CAST(@date AS DATETIME2(0));
DECLARE @now DATETIME2(0) = DATEADD(hour, 18, @day);

DECLARE @steps TABLE (step INT PRIMARY KEY, event_type NVARCHAR(30));
INSERT INTO @steps VALUES (1, N'picked_up'), (2, N'in_transit'), (3, N'at_depot'),
                          (4, N'out_for_delivery'), (5, N'delivered');
DECLARE @cities TABLE (i INT PRIMARY KEY, city NVARCHAR(60));
INSERT INTO @cities VALUES (0, N'Milano'), (1, N'Roma'), (2, N'Torino'), (3, N'Napoli'),
                           (4, N'Bologna'), (5, N'Firenze');

-- 1. Every open shipment moves one step.
DECLARE @moves TABLE (shipment_id INT PRIMARY KEY, next_step INT, event_time DATETIME2(0));
INSERT INTO @moves (shipment_id, next_step, event_time)
SELECT s.shipment_id, p.step + 1, DATEADD(hour, 8 + s.shipment_id % 8, @day)
FROM dbo.shipments s JOIN @steps p ON p.event_type = LOWER(s.status)
WHERE p.step < 5;

INSERT INTO dbo.tracking_events (shipment_id, event_type, event_time, location, loaded_at)
SELECT m.shipment_id, st.event_type, m.event_time,
       CASE m.next_step WHEN 5 THEN s.destination_city ELSE N'Depot ' + s.destination_city END,
       DATEADD(minute, 10, m.event_time)
FROM @moves m JOIN @steps st ON st.step = m.next_step JOIN dbo.shipments s ON s.shipment_id = m.shipment_id
ORDER BY m.shipment_id;

UPDATE s SET status = st.event_type, updated_at = m.event_time
FROM dbo.shipments s JOIN @moves m ON m.shipment_id = s.shipment_id JOIN @steps st ON st.step = m.next_step;

-- 2. Two new shipments, with parcels (1 + id % 2) and a picked_up event.
DECLARE @new TABLE (shipment_id INT PRIMARY KEY, created_at DATETIME2(0), origin_city NVARCHAR(60));
INSERT INTO dbo.shipments (customer_id, origin_city, destination_city, service_level, status,
                           promised_date, created_at, updated_at)
OUTPUT inserted.shipment_id, inserted.created_at, inserted.origin_city INTO @new
SELECT (2 * @d + v.j - 2) % 15 + 1, o.city, d.city,
       CASE WHEN v.j = 2 THEN N'express' ELSE N'standard' END, N'picked_up',
       DATEADD(day, CASE WHEN v.j = 2 THEN 2 ELSE 5 END, @date),
       DATEADD(hour, 8 + v.j, @day), DATEADD(hour, 9 + v.j, @day)
FROM (VALUES (1), (2)) AS v(j)
JOIN @cities o ON o.i = (@d + v.j) % 6
JOIN @cities d ON d.i = (@d + v.j + 3) % 6;

INSERT INTO dbo.tracking_events (shipment_id, event_type, event_time, location, loaded_at)
SELECT shipment_id, N'picked_up', DATEADD(hour, 1, created_at), origin_city, DATEADD(minute, 70, created_at)
FROM @new ORDER BY shipment_id;

INSERT INTO dbo.parcels (shipment_id, weight_kg, length_cm, width_cm, height_cm, created_at)
SELECT n.shipment_id, CAST(0.50 + ((n.shipment_id * 7 + x.seq * 3) % 20) * 0.75 AS DECIMAL(8,2)),
       20 + (n.shipment_id * 3) % 40, 15 + (n.shipment_id * 5) % 25, 10 + x.seq * 4, n.created_at
FROM @new n JOIN (VALUES (1), (2)) AS x(seq) ON x.seq <= 1 + n.shipment_id % 2
ORDER BY n.shipment_id, x.seq;

-- 3. Every third day: one late-arriving event (event two days old, loaded now).
IF @d % 3 = 0
  INSERT INTO dbo.tracking_events (shipment_id, event_type, event_time, location, loaded_at)
  SELECT s.shipment_id, N'at_depot', DATEADD(hour, 12, DATEADD(day, -2, @day)),
         N'Depot ' + s.destination_city, @now
  FROM dbo.shipments s WHERE s.shipment_id = (@d * 7) % 30 + 1;

-- 4. One customer changes email (snapshot exercise).
UPDATE dbo.customers
SET email = CONCAT(N'contact', customer_id, N'.day', @d, N'@example.com'), updated_at = @now
WHERE customer_id = (@d - 1) % 15 + 1;

COMMIT TRANSACTION;
GO
```

- [ ] **Step 5: Check days 1, 2, 3 and the reset**

Run: `for i in 1 2 3; do ./run.sh advance; ./run.sh status; done; ./run.sh reset; ./run.sh status`
Expected: the counts of the table "Expected row counts" for days 1, 2, 3; after `reset`, the
day 0 counts. If a count differs, compare with the derivation first; report the difference
before changing the expected values.

- [ ] **Step 6: Check determinism**

Run twice: `./run.sh reset; ./run.sh advance; ./run.sh advance;` then
`docker compose exec -T sqlserver bash -c '/opt/mssql-tools18/bin/sqlcmd -C -b -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -d shipping -h -1 -W -Q "SET NOCOUNT ON; SELECT CHECKSUM_AGG(CHECKSUM(*)) FROM dbo.tracking_events; SELECT CHECKSUM_AGG(CHECKSUM(*)) FROM dbo.shipments"'`
Expected: the same two values in both runs.

- [ ] **Step 7: Leave the source at day 0** — `./run.sh reset`. Comment on issue `#N` with the
  status outputs. No commit.

---

### Task 6: dbt source and smoke model, end to end (Part S)

**Files:** `DBT/models/shipping/_sources.yml` (final), `DBT/models/shipping/shipping_smoke.sql`.

- [ ] **Step 1: `_sources.yml`** — the variant that passed in Task 4, with the 4 tables:

```yaml
version: 2
sources:
  - name: shipping
    description: Local SQL Server shipping source (sqlserver-source/MANUAL.html), read through the Spark JDBC catalog mssql.
    # <the database/schema/quoting lines of the variant that passed in Task 4>
    tables:
      - name: customers
        description: Sender customers. Defects - one NULL email, one country code with trailing spaces.
      - name: shipments
        description: One row per shipment; status changes over simulated days.
        loaded_at_field: updated_at
        freshness:
          warn_after: {count: 2, period: day}
      - name: parcels
        description: Parcels of a shipment. Defects - a shipment without parcels, a parcel with weight 0.
      - name: tracking_events
        description: Scan events. Defects - one duplicated event, late-arriving events every third day.
        loaded_at_field: loaded_at
```

Replace the comment line with the exact lines of the passing variant (if variant c passed, no
extra line: the macro handles it). No `<...>` may stay in the file.

- [ ] **Step 2: `shipping_smoke.sql`**

```sql
-- Smoke model: proves that dbt-spark reads SQL Server and writes Iceberg on Nessie.
-- Spec 2026-11-24-extra-jdbc-sources, 5.7. Not an exercise solution.
{{ config(materialized='table', file_format='iceberg', schema='shipping_smoke') }}

select shipment_id, customer_id, status, updated_at
from {{ source('shipping', 'shipments') }}
```

- [ ] **Step 3: End to end (spec 7.3)**

```bash
cd /home/admin/work/academy/dbt-iceberg-lab && . .venv/bin/activate && unset DBT_PROFILES_DIR
(cd sqlserver-source && ./run.sh reset)
dbt run --profiles-dir . -s shipping_smoke
dbt show --profiles-dir . --inline "select count(*) as n from shipping_smoke.shipping_smoke"
(cd sqlserver-source && ./run.sh advance)
dbt run --profiles-dir . -s shipping_smoke
dbt show --profiles-dir . --inline "select count(*) as n from shipping_smoke.shipping_smoke"
dbt source freshness --profiles-dir . -s source:shipping
(cd sqlserver-source && ./run.sh reset)
```

Expected: `n = 30`, then `n = 32`; freshness runs (warn is acceptable: simulated dates are in
2026-03). The Iceberg table is in Nessie: `cd LAB && make sql-nessie` →
`SHOW TABLES IN shipping_smoke` lists `shipping_smoke`.

- [ ] **Step 4: Check git in the dbt project** — `git -C DBT status --short` is empty.
  Comment on issue `#N` with the outputs. No commit.

---

### Task 7: Manual (Part S) — main agent (Opus) writes it

**Files:** create `DBT/sqlserver-source/MANUAL.html`.

- [ ] **Step 1: Load the `artifact-design` skill for page rules** (single HTML file, tokens on
  `:root`, light and dark mode, inline SVG, no external scripts). The file is local; it is
  not published.

- [ ] **Step 2: Write the manual** with the sections of spec 5.6:

1. Purpose and quick start (`run.sh up`, `init`, `status`; lab with `nessie,thrift`; the files
   in `LAB/local/spark/`).
2. Data model: inline SVG ER diagram of the 4 tables, column tables with SQL Server type and
   Spark type (from F12).
3. Defects: table with table, row, defect, dbt test or staging fix.
4. Simulated time: what `advance` does, the table "Expected row counts", the late event of
   day 3 (shipment `(3 * 7) % 30 + 1 = 22`), the customer email change per day.
5. Exercises: (a) staging models with cleaning (trim, lower, dedup); (b) generic tests and one
   singular test; (c) incremental model on `tracking_events` by `loaded_at`, then by
   `event_time` to see the late event lost; (d) snapshot of `shipments` (timestamp strategy on
   `updated_at`) and of `customers`; (e) source freshness.
6. Solutions: in a `<details>` element per exercise, closed by default.
7. Troubleshooting: SQL Server not healthy (memory, password policy), `No suitable driver`,
   connection refused, `dbt` reads the lab profile (`DBT_PROFILES_DIR` set).

- [ ] **Step 3: Check** — open the file in a browser or with `python3 -m http.server` from
  the directory; check that every SVG shows in light and dark mode; `git -C DBT status --short`
  is empty.

---

### Task 8: PR, issue, handoff

- [ ] **Step 1: Review** — dispatch a Sonnet reviewer on `git diff main...feat/extra-jdbc-sources`
  (Part L only). The main agent judges the findings.

- [ ] **Step 2: Push and PR**

```bash
cd LAB && git push -u origin feat/extra-jdbc-sources
gh pr create --title "Extra JDBC sources for the lab Spark (LAB_EXTRA_DIR)" --body "$(cat <<'EOF'
Closes #N

- `LAB_EXTRA_DIR` (default `./local/spark`, git-ignored): `jars/` on the driver class path,
  `conf/*.conf` appended by the entrypoint; mounted read-only in `spark` and `spark-thrift`.
- `host.docker.internal` in `spark` and `spark-thrift`.
- `tests/extra-dir.sh`; README section "Local files and extra JDBC sources".
- Spec and plan: `docs/superpowers/specs/2026-11-24-extra-jdbc-sources-design.md`,
  `docs/superpowers/plans/2026-11-24-extra-jdbc-sources.md`. NOTES D21, F12 on `main`.

Regression on nessie (user decision): results in #N.
EOF
)"
```

No "Generated with" line. The user merges.

- [ ] **Step 3: Tick the checklist of issue `#N`**, update `docs/HANDOFF.md` on `main`.

---

## Self-review record

- Spec coverage: 4.1-4.6 → Tasks 1-2; 5.1-5.2 → Task 3; 5.3-5.5 → Tasks 3, 5; 5.6 → Task 7;
  5.7 → Task 6; 5.8 → Task 4; 6 → Task 4; 7.1 → Tasks 1-2; 7.2 → Tasks 3, 5; 7.3 → Task 6;
  8 → Tasks 1 (empty dir, `.conf` filter), 4 (source down), 2 (README troubleshooting); 9 →
  conventions (profiles), Task 3 Step 2 (disk).
- Deviation from spec 5.5: no `reset.sql`; `run.sh reset` runs the init scripts again (spec
  updated). Seed has 91 events, not about 150 (spec updated).
- Values fixed at execution, by a command in the plan: image tag (Task 3 Step 3), driver
  version (Task 4 Step 1), variant a/b/c (Task 4 Step 6), type mapping (Task 4 Step 3).
