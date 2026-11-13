# Lab adaptation request: run Apache Hop native Spark pipelines on the Iceberg lab

**Audience:** the agent working on `iceberg-platform-lab`.
**From:** Apache Hop analysis session (2026-11-13).
**Status:** requirements + proposed design. Items marked **VERIFY** are unconfirmed and must be
checked before implementation.

## 1. Goal

Let a user run Apache Hop pipelines on the lab's existing Spark (container `spark`, `local[*]`)
using Hop's **native Spark engine** (not Apache Beam). Hop itself stays on the user's PC and
reaches the lab only through the existing SSH/SSM access path.

## 2. Hard constraints (must hold after the change)

1. **Catalog choice stays a user decision at configuration time.** Nessie and Polaris are
   mutually exclusive, selected as today (`COMPOSE_PROFILES` → `LAB_CATALOGS` → rendered
   `spark-defaults.conf`). Nothing in this change may force one catalog or enable both.
2. **No new exposure.** No new published ports beyond `127.0.0.1`, no security-group changes.
   Access stays SSH tunnel / SSM, as documented in `README.md` and `aws/README-aws.md`.
3. **Spark stays local** (`local[*]` in container `spark`). No master/worker cluster in this scope.
4. **No Hop container in the lab.** The lab receives only two files per run (see §3).
5. Existing services and tests (Jupyter, Thrift, dbt, ELT, Trino, RustFS variant) keep working.

## 3. How Hop runs on Spark (context for the lab agent)

Hop's native Spark engine is submitted as an ordinary Spark application:

```bash
spark-submit \
  --master 'local[*]' \
  --class org.apache.hop.spark.run.MainSpark \
  /path/hop-native-spark4-submit.jar \
  --HopProjectPackage=/path/project.zip \
  --HopPipelinePath=pipelines/my-pipeline.hpl \
  --HopRunConfigurationName=lab-spark \
  --HopConfigFile=/path/hop-env.json        # optional, Hop variables
```

- **Fat jar** (`hop-native-spark4-submit.jar`, a few hundred MB): Hop engine + plugins, built on
  the PC with `hop-conf.sh --generate-fat-jar=… --spark-client-version=native-provided`. It
  **excludes Spark/Scala** (uses the cluster's) but **includes** the Iceberg runtime
  `iceberg-spark-runtime-4.1_2.13-1.11.0` and Delta jars.
- **Project package** (`project.zip`): pipelines + Hop metadata JSON, built on the PC with
  `hop-conf.sh --export-spark-project=…`.
- **`--HopConfigFile`**: JSON file of Hop variables, format:
  `{"variables":[{"name":"X","value":"…","description":"…"}]}`.
- `MainSpark` **reuses the active SparkSession** created by `spark-submit`, so it inherits the
  lab's `spark-defaults.conf` (Iceberg extensions, catalogs, S3 settings). When a pipeline uses
  Hop's Lake Table transforms, Hop **verifies** that the Iceberg session extension and the
  referenced catalog (`spark.sql.catalog.<name>`) are already configured in the session, and
  fails with an explicit error otherwise.

Versions required by the Hop plugin: **Spark 4.1.x, Scala 2.13, Iceberg 1.11.0, Java 21**.
The lab already matches Spark 4.1.3 / Scala 2.13 / Iceberg 1.11.0 (`VERSIONS.md`).

## 4. Required changes

### R1 — Java 21 in the Spark image (blocking)

Today: `SPARK_BASE_IMAGE=apache/spark:4.1.3-scala2.13-java17-python3-ubuntu`. Hop is compiled
for Java 21 (class file 65); on Java 17 `MainSpark` fails with `UnsupportedClassVersionError`.

- Switch the base image to
  `SPARK_BASE_IMAGE=apache/spark:4.1.3-scala2.13-java21-python3-ubuntu`.
  **Verified (Docker Hub registry API, 2026-11-13):** the tag exists in `apache/spark` (and in
  `library/spark`), for amd64 and arm64. Same Spark/Scala/Python line as the current java17 tag,
  so only the Java version changes. No custom image build is needed.
- Applies to both `spark` and `spark-thrift` (same image).
- Update `VERSIONS.md` and `.env.example`.
- **VERIFY** regression: Jupyter/PySpark, Thrift Server, dbt, ELT and existing `tests/*.sh`
  pass on Java 21.

### R2 — Drop zone for Hop artifacts

Add a bind mount on service `spark`, e.g. `./hop` → `/workspace/hop` (read/write), with:

```
hop/
  dist/        # fat jar(s) + project packages uploaded from the PC
  env/         # generated hop-env.json (see R4)
  out/         # optional local outputs / execution information
```

- Add `hop/dist/*`, `hop/out/*` and `hop/env/*` to `.gitignore` (keep the folders with `.gitkeep`).
- Ownership must match `LAB_UID` so the `spark` user can read uploads.

### R3 — Upload path from the PC (SSH and SSM)

- **SSH users:** `scp` into `<lab>/hop/dist/` is enough; document it.
- **SSM-only users:** no `scp`. Proposed: upload to `s3://${S3_BUCKET}/hop-artifacts/` from the
  PC, then a make target on the VM copies it into `hop/dist/` (`aws s3 cp`). This needs:
  - an IAM statement allowing the VM role `s3:GetObject`/`s3:ListBucket` on `hop-artifacts/*`
    (`aws/iam/vm-role-policy.json`, `aws/setup.sh`);
  - user-side permission to put objects there (document, do not automate user credentials).
  - **Decide** whether this is in scope; SSH-only is acceptable for a first iteration.

### R4 — Catalog-neutral Hop variables (preserves constraint 1)

Hop pipelines must not hard-code `nessie` or `polaris`. The lab generates a Hop variables file
reflecting the **currently selected** catalog, rendered at container start next to
`spark-defaults.conf` (same mechanism as `spark/entrypoint.sh` / `render.sh`):

`/workspace/hop/env/hop-env.json`:

```json
{
  "variables": [
    { "name": "LAKE_CATALOG", "value": "<selected catalog name: nessie | polaris | rest>",
      "description": "Spark catalog configured in spark-defaults.conf for this lab instance" },
    { "name": "HOP_DATA", "value": "file:///workspace/hop/out",
      "description": "Local data root for non-table outputs" }
  ]
}
```

- Exactly one catalog value, derived from `LAB_CATALOGS`. If several profiles could ever be
  active, fail rendering with a clear message rather than guessing.
- Must contain **no secrets** (Polaris credentials stay only in `spark-defaults.conf`;
  `tests/check-no-secrets.sh` should cover the new file).
- **Verified on the Hop side (code analysis, 2026-11-13):** Lake Table handlers resolve the whole
  TABLE identifier with Hop variables (`SparkLakeTableSupport.resolveTableIdentifier`), so
  `${LAKE_CATALOG}.<namespace>.<table>` works. When the transform's optional "catalog metadata"
  field is left blank, Hop does not require a Hop-side catalog definition and relies on the
  catalog already configured in the Spark session — i.e. the lab's rendered
  `spark-defaults.conf`. Consequence for the lab: the Spark catalog names (`nessie`, `polaris`,
  `rest`) and their `spark.sql.catalog.*` settings stay exactly as they are; no alias catalog and
  no `spark.sql.defaultCatalog` change is needed. A missing catalog surfaces only as a Spark
  error at read/write time, so the rendered `LAKE_CATALOG` must always match the catalog
  actually configured in `spark-defaults.conf` (derive both from the same `LAB_CATALOGS` value).

### R5 — Submit target

Add a make target that runs a Hop pipeline in container `spark`:

```make
hop-run:  ## PIPELINE=pipelines/x.hpl PACKAGE=project.zip [JAR=hop-native-spark4-submit.jar] [RUN_CONFIG=lab-spark]
	docker compose exec -T spark spark-submit \
	  --master 'local[*]' \
	  --class org.apache.hop.spark.run.MainSpark \
	  /workspace/hop/dist/$(JAR) \
	  --HopProjectPackage=/workspace/hop/dist/$(PACKAGE) \
	  --HopPipelinePath=$(PIPELINE) \
	  --HopRunConfigurationName=$(RUN_CONFIG) \
	  --HopConfigFile=/workspace/hop/env/hop-env.json
```

- Defaults: `JAR=hop-native-spark4-submit.jar`, `RUN_CONFIG=lab-spark`.
- Validate inputs (files exist, `PIPELINE` set) with clear errors; exit code must propagate
  (Hop's `MainSpark` exits non-zero on pipeline failure).
- Optional: a thin script (e.g. `scripts/hop-run.sh`) so the PC can trigger it with one
  `ssh <vm> 'cd <lab> && make hop-run …'` or via SSM `send-command`.
- **VERIFY**: `spark.driver.memory 4g` is sufficient; expose an override
  (`SPARK_DRIVER_MEMORY` or `--driver-memory`) if needed.

### R6 — Classpath sanity

The fat jar bundles `iceberg-spark-runtime` 1.11.0 while the image already has the same jar in
`$SPARK_HOME/jars` (plus `iceberg-aws-bundle`). Same version, so expected harmless (Spark's
default classpath order puts `$SPARK_HOME/jars` first).
**VERIFY** with a smoke run; if conflicts appear, the Hop side will produce a fat jar without the
Iceberg runtime instead of changing the lab.

### R7 — Documentation and tests

- `README.md`: new section "Running Apache Hop pipelines", covering upload (SSH/SSM),
  `make hop-run`, how the selected catalog is exposed as `LAKE_CATALOG`, and the Java 21 note.
- `NOTES.md`: record the decisions (Java 21, drop zone, catalog-neutral variable).
- Tests (style of existing `tests/*.sh`):
  - image runs Java 21 (`java -version` inside `spark`);
  - `hop-env.json` renders with the selected catalog for each profile and contains no secrets;
  - `make hop-run` validates missing inputs;
  - end-to-end smoke (optional, needs artifacts from the Hop side): run a sample package once
    with Nessie and once with Polaris, read back the written Iceberg table via `spark-sql`.

## 5. Out of scope

- Spark standalone/cluster mode, Spark Connect, Livy, any remote-submit service.
- Hop GUI/Server in the lab.
- Hop project content, run configuration and fat jar build (provided by the Hop side).

## 6. Provided by the Hop side (for the end-to-end test)

- A sample project package with one pipeline that writes and reads an Iceberg table via
  `${LAKE_CATALOG}.<namespace>.<table>`, and a Native Spark run configuration `lab-spark` with
  **empty Spark master** (so `spark-submit --master` wins).
- Hop-side conventions (no lab action): Lake Table transforms use 3-part identifiers
  (2-part identifiers are mis-routed by Iceberg Maintenance in the current Hop code) and leave
  the "catalog metadata" field blank so the lab's session catalog is used.
- The `native-provided` fat jar built from the same Hop version.

## 7. Acceptance criteria

1. `docker compose exec spark java -version` reports 21; all pre-existing tests pass.
2. With the Nessie profile: `make hop-run …` succeeds and the Iceberg table is visible from
   `spark-sql` in catalog `nessie`.
3. Same with the Polaris profile, catalog `polaris`, with no change to the Hop artifacts.
4. No new published ports; no secrets in `hop/` or in git.
