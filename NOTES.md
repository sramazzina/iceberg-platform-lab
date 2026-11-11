# Notes

Deviations from the requirements (`docs/req/prompt-agente-lab-iceberg-polaris-nessie.md`)
and conflicts between the requirements and the project documentation.
Each entry: what the requirement says, what the lab does, and why.

## Deviations

### D1 — Repository root name
- Requirement (section 7): the root folder is `iceberg-catalog-lab/`.
- Lab: the root is the repository `iceberg-platform-lab`.
- Why: the repository already existed with this name. The layout below the root follows section 7.

### D2 — `aws/setup.sh` uses the existing VM role
- Requirement (section 6.4): `setup.sh` creates the instance profile.
- Lab: the VM and its instance profile already exist. `setup.sh` finds the VM role
  from `INSTANCE_ID` and adds the inline policy `iceberg-lab-vm` to it.
  `teardown.sh` removes only that inline policy.
- Why: the VM was created before the lab, with its own role.

### D3 — The VM role can list `polaris/`
- Requirement (section 6.1): the VM role has S3 access to `nessie/` and `rest/`.
- Lab: the VM role can also **list** (not read, not write) `polaris/` and the bucket root.
- Why: scenario 2 and the smoke tests use `aws s3 ls` to show the Polaris layout.
  Reads and writes under `polaris/` still need credentials vended by Polaris.

### D4 — Phase 1 test object prefix
- Requirement (phase 1): read and write a test file in `s3://${S3_BUCKET}/`.
- Lab: the test writes under `s3://${S3_BUCKET}/rest/_smoke/`.
- Why: the VM role has no write access to the bucket root (least privilege).

### D5 — Python packages are pinned in `spark/requirements.txt`
- Requirement (rule 4.2): pin every version in `.env`.
- Lab: image tags and JAR versions are in `.env`; Python packages are in `spark/requirements.txt`.
- Why: pip reads a requirements file natively; one build argument per package would add noise.

### D6 — Python 3.10 in the Spark image
- The official `apache/spark:4.1.3` images are based on Ubuntu 22.04, so Python is 3.10.
  Python 3.10 reached end of life in October 2026. pandas and pyarrow are pinned to the
  last releases that support Python 3.10 (2.3.3 and 25.0.1). Accepted for a test lab.

### D7 — Iceberg client 1.11.0, not the latest 1.12.0
- Polaris 1.8.0 and Nessie 0.109.0 are built against Iceberg 1.11.0. The lab uses the same
  client version, so that compatibility is not a variable in the comparison.

### D8 — `teardown.sh` keeps the IMDS hop limit
- Requirement (section 6.5): `teardown.sh` removes everything that `setup.sh` created.
- Lab: `setup.sh` sets the hop limit of the existing VM to 2. `teardown.sh` does not set it
  back. It prints the command that restores hop limit 1.
- Why: `setup.sh` changes a setting of a VM that it did not create. The previous value is
  not recorded, so the script cannot restore it safely.

### D9 — Phase 3 (Nessie) before Phase 2 (Polaris)
- Requirement (section 8): the phases run in the order 2 (Polaris), 3 (Nessie), 4 (baseline).
- Lab: Phase 3 runs before Phase 2 (user decision, 2026-10-28).
- Why: Nessie needs no credential vending and no bootstrap job, so it is the shorter path to a
  first catalog. `spark-defaults.conf` stays a static file until Phase 2, because only the
  Polaris catalog block needs secrets.

### D10 — Nessie object-store health check disabled
- Nessie 0.109.0 checks each warehouse with S3 `HeadBucket` in its readiness check.
- The VM role allows `s3:ListBucket` only with an `s3:prefix` condition (least privilege),
  so `HeadBucket` returns 403 and the readiness check reports DOWN.
- Lab: `NESSIE_CATALOG_OBJECT_STORES_HEALTH_CHECK_ENABLED=false`. The object-store check stays
  in the readiness check, but it reports UP without an S3 call. The readiness check still
  covers the database connection. `tests/catalog-smoke.sh nessie` checks the S3 access.

### D11 — The catalogs are optional
- Requirement (sections 5.1 and 7): the stack has the services `polaris` and `nessie`, and the
  Makefile has the target `up-baseline`.
- Lab: each catalog is a Compose profile (`polaris`, `nessie`, `baseline`). The catalogs
  are off by default. `COMPOSE_PROFILES` in `.env` selects them. There is no `up-baseline`: add
  `baseline` to `COMPOSE_PROFILES`.
- Why: user decision (2026-10-29). The user chooses the catalog for each test. The catalogs do
  not have to run together. The requirements were changed to match.

### D12 — `polaris-bootstrap` is required
- Spec (section 5): add `polaris-bootstrap` only if the Polaris docs require it.
- Lab: Polaris 1.8.0 with `relational-jdbc` does not create its tables. The admin tool creates
  them and the root principal. A second run skips, so the job runs on every `make up`.
- The job reads the root credentials from a private file (`bootstrap -f`), not from the command
  line: the image entrypoint (`run-java.sh`) writes the full command line to the log.

### D13 — `polaris-setup` reads JSON with `sed`
- Requirement (section 5.1): the setup image has `curl` and `jq`.
- Lab: the pinned image `alpine/curl` has no `jq`. The script is POSIX `sh` and reads the few
  JSON fields it needs with `sed`.
- Why: `apk add jq` at every start needs network access and installs an unpinned version.

### D14 — Phases 5 and 6 deferred
- Requirement (section 8): Phase 5 writes the scenario notebooks and Phase 6 writes
  `EVALUATION.md`. Section 10 lists both as completion criteria.
- Lab: Phases 5 and 6 are deferred to a later stage (user decision, 2026-10-29). The lab has
  no scenario notebooks, no `make scenarios` and no `EVALUATION.md`.
- Why: the current scope is to build the platform for study, not to compare the catalogs.

### D15 — RustFS for the on-premise variant
- The spec names MinIO or RustFS for on-premise storage. MinIO Community Edition is archived
  (2026) and is AGPLv3. The lab uses RustFS 1.0.4 (Apache-2.0): it implements STS
  `AssumeRole`, so Polaris vends credentials as on AWS.
- Rejected: Versity S3 Gateway (plain files, but no STS), SeaweedFS (too many components),
  Garage (AGPLv3), Ceph RGW (heavy, LGPL), S3Proxy (no STS).
- RustFS keeps objects in an internal format. The user accepts it: the web console shows
  the storage (user decision, 2026-10-29).
- Design: `docs/superpowers/specs/2026-10-29-rustfs-onprem-design.md`.

### D16 — ELT with dbt and a Spark Thrift Server
- Requirement: not in the original requirements; user request of 2026-10-30.
- Lab: TPC-H data generated with DuckDB (`make tpch-gen`), loaded by PySpark into
  `tpch_raw` (`make tpch-load`), transformed by one dbt project (`dbt/`) with one target per
  catalog (`make dbt`). dbt-spark uses the `thrift` method with the new service
  `spark-thrift` (profile `thrift`), which external JDBC clients also use.
- Why: one generic project shows how each catalog keeps the tables of a pipeline. The
  Thrift Server gives JDBC access (DBeaver); the `session` method does not.
- Spec: `docs/superpowers/specs/2026-10-30-dbt-elt-design.md`. Findings: F7, F8.

### D17 — Trino without authentication
- Requirement: not in the original requirements; issue #54 (user request of 2026-11-11).
- Lab: the optional service `trino` (profile `trino`) uses HTTP on `127.0.0.1:8080`, with no
  password and no TLS. Any user or process on the VM can read and write every table of the
  catalogs that are on.
- Why: the lab is a single-user study platform; access from a laptop goes through the SSH
  tunnel or SSM. TLS and passwords are deferred to the Power BI work (issue #53), which needs
  them.
- Spec: `docs/superpowers/specs/2026-11-11-trino-design.md`. Finding: F10.

### D18 — Trino reads and writes, with its own Polaris principal
- Requirement: issue #54.
- Lab: Trino reads and writes the same tables as Spark. On `polaris` it authenticates as the
  dedicated principal `trino_user` (principal role `trino_role`, catalog role `lab_admin`),
  never as root. `polaris-setup` creates `trino_user` always, also when the profile `trino`
  is off, and writes `secrets/trino_user.env` (mode 600).
- Why: one principal per engine keeps the grants and the credential resets separate.
  `polaris-setup` does not need to know which engines are on.
- Spec: `docs/superpowers/specs/2026-11-11-trino-design.md`, section 8. Finding: F10.

## Findings

### F1 — Nessie S3 credentials (Nessie 0.109.0, checked 2026-10-28)
- Nessie reads and writes table metadata with its own server credentials. The lab sets
  `auth-type=APPLICATION_GLOBAL`. This uses the AWS default credential chain, which gives the
  VM instance profile. The default `auth-type` is `STATIC` (static keys).
- On the RustFS variant, the default chain reads the keys of the user `lab` that
  `docker-compose.rustfs.yml` gives to Nessie. Tested (`make smoke-test`).
- Nessie gives clients S3 access in three ways:
  - **Request signing** (on by default): the client sends every S3 request to Nessie
    (`/iceberg/v1/{prefix}/s3sign/...`) for signing. The client needs no S3 credentials.
  - **Credential vending** with STS: `client-iam` (vended to clients) and `server-iam`
    (used by Nessie). Both are off by default. They need `assume-role` (a role ARN) and,
    outside AWS, `sts-endpoint`. The lab does not test them.
  - **Client credentials**: with request signing disabled, the client uses its own credentials.
- Lab: request signing is disabled. Spark writes the data and manifest files with the VM
  instance profile, as spec section 5.3 requires for `nessie/`. Nessie writes the table
  metadata files (`*.metadata.json`). `tests/catalog-smoke.sh nessie` checks that the
  Nessie log has no `s3sign` request.
- Sources: `S3BucketOptions.java`, `S3Iam.java`, `S3ClientIam.java`, `S3ServerIam.java` and
  `site/docs/guides/iceberg-rest.md` at tag `nessie-0.109.0`.

### F2 — Nessie runs without authentication
- Nessie 0.109.0 has authentication and authorization off by default
  (`nessie.server.authentication.enabled=false`). At start it logs a warning:
  "Both authentication (AuthN) and authorization (AuthZ) are disabled".
- Lab: the warning is expected. The Nessie ports are published on `127.0.0.1` only, and the
  user reaches them through an SSH or SSM tunnel. Scenario 7 documents the Nessie
  authorization model.

### F3 — Polaris purge (Polaris 1.8.0, checked 2026-10-29)
- The catalog property `polaris.config.drop-with-purge.enabled` (default false) controls the
  server-side purge: a REST `DELETE ...?purgeRequested=true` gets HTTP 403 when it is false.
- Spark `DROP TABLE ... PURGE` does not use the server-side purge. Spark deletes the files
  itself, with the S3 credentials that Polaris vends. It works also when the property is false.
- Lab: the property stays false. `tests/catalog-smoke.sh polaris` drops its table with
  `DROP TABLE ... PURGE` and fails when a file is left under `polaris/`. The VM role cannot
  delete under `polaris/`: a left file must be removed from CloudShell.

### F4 — Where the Polaris secrets are
- The root client secret is in `.env` and in the environment of the one-shot containers
  `polaris-bootstrap` and `polaris-setup` (`docker inspect` shows it). It is not in a log or
  on a command line; `tests/polaris-service.sh` checks the bootstrap log.
- The `spark_user` credentials are in `secrets/spark_user.env` (git-ignored, mode 600). The
  Spark entrypoint reads them without exporting them and writes them into
  `/opt/spark/conf/spark-defaults.conf` (mode 600). `spark.redaction.regex` hides them in the
  Spark UI.
- The bootstrap root file `/tmp/root.yaml` (mode 600) stays in the filesystem of the exited
  `polaris-bootstrap` container until `make down` removes it.
- Accepted for a single-user lab VM, where Docker access already gives root access.

### F5 — `apache/iceberg-rest-fixture` (1.10.1, checked 2026-10-29)
- No tag matches Iceberg 1.11: the lab uses 1.10.1, the newest versioned tag. The Spark client
  is 1.11.0. The acceptance test passes with this combination.
- The default catalog is SQLite on `/tmp/iceberg_catalog.db`, which is lost when the container
  is recreated. Lab: `CATALOG_URI=jdbc:sqlite:/home/iceberg/catalog.db` on the named volume
  `rest-fixture-data`. The volume is mounted on `/home/iceberg`, the home of the image user
  `iceberg` (uid 1000): Docker gives a named volume the owner of the folder in the image. A
  folder that is not in the image (for example `/home/iceberg/data`) is owned by root, and the
  fixture cannot write it.
- The fixture listens on 8181, the host port of Polaris. Lab: host port 8183, so `polaris` and
  `baseline` can be on together.
- `GET /v1/config` gives no default to clients (`"defaults":{}`): Spark uses its own region
  (`AWS_REGION`) and the VM instance profile.
- `DROP TABLE ... PURGE`: Spark deletes the files, not the fixture. `SparkCatalog.purgeTable`
  drops the table without purge, then deletes the reachable files with the table FileIO, that
  is the VM instance profile. The fixture log shows only `JdbcCatalog - Dropped table`. This is
  the same mechanism as F3. Source:
  `spark/v4.1/spark/src/main/java/org/apache/iceberg/spark/SparkCatalog.java` at tag
  `apache-iceberg-1.11.0`. `tests/catalog-smoke.sh rest` fails when a file is left under the
  table root, and the VM role deletes it.
- On the RustFS variant, `CATALOG_S3_ENDPOINT` and `CATALOG_S3_PATH__STYLE__ACCESS` configure
  the fixture, and `spark/conf/s3-endpoint/baseline.conf` gives the same values to Spark (the
  fixture does not give them to clients). On AWS the lab passes no endpoint: an empty endpoint
  value can break `S3FileIO`.

### F6 — RustFS (1.0.4, checked 2026-10-29)
- RustFS ignores `RoleArn` in `AssumeRole`. The temporary credentials inherit the policies of
  the calling user (`polaris`), restricted by the Polaris session policy. The lab gives
  Polaris a placeholder role ARN with the fake account `123456789012`.
- The caller of `AssumeRole` must be a built-in user, not a service account: `rustfs-setup`
  creates the users with `rc admin user add` (rustfs/rustfs#4832).
- RustFS rejects a policy resource that is not an S3 ARN: `*`, `arn:aws:sts:::*`,
  `arn:aws:iam:::*` and `arn:aws:kms:...` give "invalid resource". So:
  - The `sts:AssumeRole` statement of `rustfs/setup/policy-polaris.json` has no `Resource`
    key. `AssumeRole` works with it.
  - Polaris adds a KMS statement (`arn:aws:kms:<region>:<account>:key/*`) to the session
    policy by default, and RustFS rejects the whole policy. `polaris/setup/setup.sh` sets
    `kmsUnavailable: true` in the catalog storage configuration when `S3_ENDPOINT` is set.
    Credential vending stays on. Source: `AwsStorageConfigInfo` in
    `spec/polaris-management-service.yml` at tag `apache-polaris-1.8.0`.
  - A catalog made before this change keeps its old storage configuration. Update it with
    `PUT /api/management/v1/catalogs/lab_catalog` (`currentEntityVersion` and the
    `storageConfigInfo` with `kmsUnavailable: true`).
- Nessie 0.109.0 gives `s3.path-style-access` to clients, with `s3.endpoint`. Spark needs no
  endpoint setting for the catalog `nessie`.
- The lab runs RustFS with `LAB_UID`, so the data directory belongs to the host user. The
  RustFS log warns that it cannot write `/logs`; it logs to stdout. The warning is harmless.
- `rustfs/rustfs#2766` (`DeleteObjects` and the bucket ARN) did not occur: `DROP TABLE ...
  PURGE` works on all catalogs.

### F7 — Spark Thrift Server, dbt-spark and DuckDB (checked 2026-10-30)

All checks ran on the RustFS variant (local workstation, WSL2 with Docker Desktop).

- S1: the base image `apache/spark:4.1.3-scala2.13-java17-python3-ubuntu` has
  `spark-hive-thriftserver_2.13-4.1.3.jar` and `bin/beeline`. Confirmed.
- S2: `HiveThriftServer2` starts with the lab configuration (log line `HiveThriftServer2
  started`, about 10 s). No `/tmp/metastore_db` was created: no Derby metastore in this setup.
- S3: the session key `set:hiveconf:spark.sql.defaultCatalog` sets the default catalog of a
  Thrift session. The key `spark.sql.defaultCatalog` (no prefix) is accepted but ignored
  (`current_catalog()` stays `spark_catalog`). `use:database` does not set a catalog.
  PyHive runs `USE default` when it opens a session. The `default` namespace must exist in the
  selected catalog, or the connection fails with `SCHEMA_NOT_FOUND`. dbt-spark does not pass
  the PyHive `database` argument.
- S4: Iceberg views through the REST API: supported on polaris, nessie and rest (dbt `view`
  model created, and read through a new session on all three). Polaris does not delete the
  metadata file of a dropped view, and on AWS the lab role cannot delete it. For this reason
  the staging models are tables on every catalog.
- S5: DuckDB 1.5.6 `tpch`: `install_mode` is `NOT_INSTALLED`. The extension is not statically
  linked. `INSTALL tpch` downloads it to `~/.duckdb/extensions/v1.5.6/linux_amd64/`. After the
  install, `CALL dbgen(sf = 0.001)` works (`region` has 5 rows).
- S6: authentication `NOSASL`: PyHive and Hive JDBC connect with user `spark`. With the
  default authentication, beeline works but PyHive fails: `No module named 'thrift_sasl'`
  (`dbt-spark[PyHive]==1.11.0` does not install `thrift_sasl`). Start the server with
  `--hiveconf hive.server2.authentication=NOSASL`. Use `auth: NOSASL` in the dbt profile and
  `jdbc:hive2://127.0.0.1:10000/;auth=noSasl` for beeline.
- S7: `pip check` after the install of the dbt packages: `No broken requirements found.`
- S8: dbt-spark 1.11.0 `table`, `view`, `incremental` (`merge`) with `+file_format: iceberg`:
  `PASS=3` on two consecutive runs on polaris, nessie and rest (needs the `default`
  namespace, see S3). Risk: on `rest` one run (2 threads) failed with `SQLITE_BUSY` (the
  fixture uses SQLite) and every commit then failed with `500 Unknown failure` until the
  `rest-fixture` container was restarted. After the restart, 2 threads worked on `rest`.
  On nessie, `m_incr.snapshots` has 1 row after two runs (polaris and rest: 2).

### F8 — ELT pipeline on a Linux server (checked 2026-10-31)

All checks ran on the RustFS variant, on a Linux server with Docker Engine 29.2.1.

- The RustFS variant starts on Docker Engine: `rustfs-setup` exits with code 0.
- Host port 9000 can be used by another stack on a shared server. Set `NESSIE_MGMT_PORT` in
  `.env` to publish the Nessie management port on another host port.
- `dbt debug` checks for `git`. The `spark` image installs `git` (GPL-2.0, a separate OS
  package; see `VERSIONS.md`).
- Snapshot operations of `fct_lineitem`: the first `dbt build` runs `create or replace table`
  (operation `overwrite`). The incremental `dbt run` runs `merge into` with only new keys: it
  adds files and deletes none (operation `append`). On nessie with `SF=0.01`: 45730 rows,
  then 14445 rows added (60175).
- beeline in non-interactive mode prints its prompt (`0: jdbc:hive2://…> `) in front of each
  result value. Tests remove the prompt before they compare the value.
- A test run that is stopped in the middle can leave objects under a `tpch_` prefix that no
  catalog knows. `make tpch-clean` cannot see them, and the next test reports them. Remove
  them with `aws s3 rm --recursive` on that prefix (from the `spark` container).
- beeline with `-e` waits for input when its stdin stays open: it connects, prints its prompt
  and does not run the statement. `docker compose exec -T` forwards the stdin of the caller, so
  a test run from a terminal stopped for hours in `tests/thrift-service.sh` (EC2 VM,
  2026-11-03). The server thread waited for the next client message. Ctrl+D released it.
  Reproduced on the Linux server: with an open stdin no result after 60 s; with `</dev/null`
  the result in 1.3 s. Every beeline call (`Makefile` target `dbt`, `tests/thrift-service.sh`,
  `tests/elt.sh`) reads stdin from `/dev/null`. One earlier `make dbt` run on nessie that
  stopped for 12 minutes in the beeline call that creates the namespace `default` probably
  had the same cause.
- `SF=1` on nessie, Linux server: gen 5 s, load 24 s, build 22 s, full load 20 s, run 19 s.
- `make elt-test` (`SF=0.01`), total time. Linux server with RustFS: nessie ~3 min, polaris
  ~5 min, rest ~3 min. AWS stack on the EC2 VM (2026-11-03, after the beeline fix): nessie
  6 min 55 s, polaris 9 min 32 s, rest 7 min 40 s.

### F9 — JDBC navigator and the Iceberg catalogs (Spark 4.1.3, checked 2026-11-11)

Issue #50. "V1" and "V2" are the two generations of the **Spark catalog API** (V1 = the
built-in `SessionCatalog`, `spark_catalog`; V2 = DataSource V2 `CatalogPlugin`, used by the
Iceberg `SparkCatalog`). They are not Iceberg table format versions.

Cause (read in the Spark source, `branch-4.1`):
- The Thrift Server JDBC metadata operations (`SparkGetSchemasOperation`,
  `SparkGetTablesOperation`, `SparkGetColumnsOperation`) read only the V1 `SessionCatalog`
  (`SparkOperation.catalog = sessionState.catalog`). `SparkGetCatalogsOperation` returns no
  row.
- The lab catalogs `nessie`, `polaris` and `rest` are V2 catalogs. A navigator that builds its
  tree from these calls (DBeaver, Power BI) never shows them.
- `spark.sql.defaultCatalog` does not change the metadata calls.
- Spark 4.3 adds `spark.sql.thriftServer.catalogMetadata.enabled` (SPARK-57518, default
  `false`): `getSchemas` lists the namespaces of a V2 current catalog, but `getTables` and
  `getColumns` still read `spark_catalog`. Follow-up work: Spark PR #57468 (open on
  2026-11-05).

Reproduced with beeline (Hive JDBC 2.3.10) on the EC2 VM, profiles `nessie,thrift`:
- `!metadata getSchemas` returns `default` and `global_temp`. `!tables` returns no row.
  `SHOW NAMESPACES IN nessie` returns `default` and `smoke`.
- The URL with `;?spark.sql.defaultCatalog=nessie` gives the same metadata result.

Spike: Iceberg `SparkSessionCatalog` as `spark_catalog` (throw-away Thrift Server on port
10001, every `spark.sql.catalog.nessie.*` property copied to `spark_catalog`; removed after
the test):
- `CREATE TABLE spike50.t ... USING iceberg` and `INSERT` work. The table is in Nessie
  (`nessie.commit.ref=main`; `SHOW TABLES IN nessie.spike50` on the main server lists it).
- Namespace operations go to the V1 session catalog (in-memory), not to Nessie.
  `SHOW NAMESPACES` returns only `default`, not the Nessie namespaces. The namespace must
  exist in both places: in Nessie for the table, in the V1 catalog for `CREATE TABLE`.
- `!metadata getSchemas` lists only the V1 databases. `!tables` and `!metadata getColumns`
  return no row for the Iceberg table.
- `SHOW TABLES IN spike50` also returns no row: the table list comes from the V1 catalog.
- Result: `SparkSessionCatalog` does not make the navigator show the Iceberg tables. It also
  hides the Nessie namespaces from SQL. It can cover only one catalog.

Approaches and recommendation:
- Spark 4.1 configuration: no setting shows the V2 catalogs in the navigator.
- Hive Metastore as V1 catalog (not tested): the navigator would show the tables of the
  metastore only. The Iceberg REST catalogs (`nessie`, `polaris`, `rest`) stay V2. Not
  examined further: it changes the lab architecture and does not show the REST catalogs.
- DBeaver (not tested): with the Hive JDBC driver the navigator tree comes from the metadata
  calls above. No DBeaver setting that builds the tree with SQL was found.
- Another SQL engine with catalog-aware metadata (for example Trino, issue #53 approach 2)
  shows the Iceberg catalogs as JDBC catalogs. It is a new service in the lab.
- Recommendation: keep the workaround. Use SQL with three-part names
  (`SELECT * FROM nessie.<namespace>.<table>`, `SHOW TABLES IN nessie.<namespace>`) or the
  URL with `spark.sql.defaultCatalog` (README, DBeaver section). Examine the Spark
  Thrift Server again when the follow-up of SPARK-57518 is released.
- Update 2026-11-11: Trino is now an optional service of the lab (F10). Its JDBC navigator
  shows the Iceberg catalogs, namespaces and tables.

### F10 — Trino 484 on the Iceberg REST catalogs (checked 2026-11-11)

Issues #54, #56 … #62. Image `trinodb/trino:484` (Java 25, Apache-2.0). EC2 VM, 8 GB, AWS
stack, profiles `nessie,polaris,baseline,trino`.

Image (issue #56):
- The image has no `ENTRYPOINT`; `CMD` is `launcher run --etc-dir /etc/trino`, user
  `trino:trino` (UID 1000). `bash`, `cat`, `cp`, `mkdir`, `rm` and `curl` are present; `grep`
  and `cut` are not.
- Trino starts with an arbitrary UID (`--user 1234`) and the configuration in
  `/tmp/trino-etc`. The lab runs it with `LAB_UID`, so that it can read
  `secrets/trino_user.env` (mode 600).
- `/usr/lib/trino/bin/health-check` reads the port from `/etc/trino/config.properties`, not
  from `/tmp/trino-etc`. The property is absent there, so the script falls back to 8080. The
  Compose health check relies on this fallback: if the port changes, the health check must
  change too.

Points that the spec marked NOT CONFIRMED (section 4), all confirmed by
`tests/trino-service.sh` on the AWS stack:
- Polaris: OAuth2 as `trino_user` (`iceberg.rest-catalog.security=OAUTH2`) and vended
  credentials work. Trino masks the credential in its log (`[REDACTED]`).
- Nessie: the Iceberg REST endpoint `/iceberg/main` works.
- Rest fixture 1.10.1 works.
- Trino reads the Iceberg 1.11.0 tables that Spark 4.1.3 writes, and Spark reads the tables
  that Trino writes (`CREATE TABLE AS`), on all three catalogs.
- On `nessie` and `rest` the compose file passes `AWS_ACCESS_KEY_ID` and
  `AWS_SECRET_ACCESS_KEY` empty: the AWS SDK default chain falls back to the VM instance
  profile. No workaround is necessary.

DBeaver navigator (issue #62), checked by the user through the SSH tunnel
(`-L 8080:127.0.0.1:8080`), Trino driver, `jdbc:trino://localhost:8080`, no password:
- The navigator shows the catalogs `nessie`, `polaris` and `rest` and their namespaces.
- It shows the tables, their columns and their data (a table written by Spark in each
  catalog). This closes the gap of F9 for a JDBC navigator.
- A namespace with no table shows no table: the test scripts delete their tables at the
  end. DBeaver caches the metadata: refresh the connection (F5) after a change.

Memory (`docker stats`, during `tests/trino-service.sh`): trino 704 MiB / 3 GiB, spark
514 MiB, nessie 276 MiB / 1 GiB, polaris 240 MiB / 1 GiB, rest-fixture 115 MiB / 512 MiB,
postgres 69 MiB. All three catalogs and Trino fit on the 8 GB VM without `thrift`.

Deviations from the spec (plan `docs/superpowers/plans/2026-11-11-trino.md`):
1. The S3 file system property of Trino 484 is `fs.s3.enabled`, not `fs.native-s3.enabled`.
2. The query memory limits keep the Trino defaults (`query.max-memory-per-node` and
   `memory.heap-headroom-per-node` = 30% of the heap), so they follow `TRINO_HEAP`.
3. The health check is the script of the image (see above), not a custom `curl` command.
4. `spark/entrypoint.sh` skips the profile `trino`, like `thrift`.
5. The entrypoint reads the credentials file from `LAB_TRINO_SECRETS` (default
   `/run/lab-secrets/trino_user.env`), so that `tests/trino-config.sh` can use a test file.
6. `tests/lint.sh` runs `bash -n`, not `shellcheck` (not installed on the VM).

Not verified with a live run: Trino on the RustFS variant (not configured on the EC2 VM).
Only the Compose configuration is checked (`tests/compose-variant.sh`). Follow-up: issue #63.

## Open investigations

Filled in during the later phases.

- Not verified: the RustFS variant on macOS. The variant is verified on Windows (WSL2) with
  Docker Desktop and on Linux with Docker Engine (F8).
