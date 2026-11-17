# Design — Apache Hop native Spark pipelines on the lab Spark

- Date: 2026-11-13
- Issue: #65
- Input request: `docs/lab-adaptation-for-hop-native-spark.md` (from the Apache Hop analysis
  session)
- Status: approved by the user in the brainstorming of 2026-11-13

## 1. Goal

A user runs an Apache Hop pipeline with the Hop native Spark engine
(`org.apache.hop.spark.run.MainSpark`) on the lab Spark (container `spark`, `local[*]`). Hop
stays on the user PC. The lab receives two files per run: the Hop fat jar and the Hop project
package. The first iteration is a fast trial on the EC2 VM.

## 2. Scope

In scope:

1. Java 21 in the `spark` image (also used by `spark-thrift`). The Java 21 image replaces the
   Java 17 image.
2. A drop zone `./hop` mounted in container `spark`.
3. `make hop-run`, through the script `hop/run.sh`.
4. A Hop variables file `hop/env/hop-env.json` with the catalog of the run.
5. Tests, regression on the EC2 VM, `README.md`, `NOTES.md`, `VERSIONS.md`.

Out of scope:

- Upload through S3 and SSM, and the IAM changes for it (request R3, SSM part). Upload is
  `scp` only.
- A rule that only one catalog is on. The user wants the catalogs to be mutually exclusive,
  but the lab does not enforce it today and the EC2 VM runs several catalogs together. An
  enforcement is a separate change.
- A parameter for the Spark driver memory. Add it only if the trial shows that 4g is not
  enough.
- Spark standalone or cluster mode, Spark Connect, Livy, Hop GUI or Hop Server in the lab.
- Hop project content, run configuration and fat jar build (Hop side).

## 3. Decisions (brainstorming of 2026-11-13)

| # | Decision | Why |
|---|---|---|
| 1 | Minimal scope for a fast trial (section 2) | The user needs a trial of Hop on Spark soon |
| 2 | The catalog is a parameter of each run (`CATALOG=`), optional when only one catalog is configured | Works with one catalog (the user intent) and with the current multi-catalog setup of the EC2 VM |
| 3 | Trial on the EC2 VM. Plan execution and verification by a Claude Code session on the VM | The trial runs there; the workstation can verify only a part (nessie, RustFS) |
| 4 | Approach A: Java 21 is the standard image; the Java 21 image replaces the Java 17 image (no build next to it) | Same Spark, Scala and Python line; one image to maintain; disk on the VM |
| 5 | `hop-env.json` is written by `hop/run.sh` for each run, not by the container entrypoint | The catalog is chosen for each run (decision 2) |
| 6 | The list of catalogs comes from the rendered `spark-defaults.conf` of the running container | `LAKE_CATALOG` then always matches a catalog that Spark has |

## 4. Design

### 4.1 Java 21 image

- `SPARK_BASE_IMAGE=apache/spark:4.1.3-scala2.13-java21-python3-ubuntu` in `.env.example`.
  The request reports that the tag exists for amd64 and arm64 (Docker Hub registry API,
  2026-11-13). The plan verifies it again before the build.
- `VERSIONS.md`: Spark row (Java 21, new tag and source URL) and Python row (source URL).
- `spark/Dockerfile` does not change.
- The image name stays `iceberg-lab-spark:${ICEBERG_VERSION}`. The new build takes the tag.
- Replacement procedure on a host (README and plan), in this order:
  1. Stop and remove the containers `spark` and `spark-thrift`.
  2. Remove the images `iceberg-lab-spark:<ICEBERG_VERSION>` and
     `apache/spark:4.1.3-scala2.13-java17-python3-ubuntu`.
  3. Set `SPARK_BASE_IMAGE` in `.env` to the Java 21 tag.
  4. Run `make up`.
- Test: `tests/spark-image.sh` checks that `java -version` reports version 21.

### 4.2 Drop zone

- Service `spark` gets the volume `./hop:/workspace/hop` (read and write). `spark-thrift` does
  not get it.
- Tracked layout:

  ```text
  hop/
    run.sh        # tracked: the script of make hop-run (section 4.3)
    dist/.gitkeep # fat jars and project packages, copied from the PC with scp
    env/.gitkeep  # hop-env.json, written by run.sh
    out/.gitkeep  # optional outputs of the pipelines (HOP_DATA)
  ```

- `.gitignore`: `hop/dist/*`, `hop/env/*`, `hop/out/*`, with exceptions for the `.gitkeep`
  files.
- Ownership: the files copied with `scp` belong to the host user. The container user `spark`
  has the UID `LAB_UID` (the host UID), so it can read them.

### 4.3 `make hop-run` and `hop/run.sh`

Make target:

```text
make hop-run PIPELINE=<path in package> PACKAGE=<file in hop/dist> \
  [CATALOG=<catalog>] [JAR=hop-native-spark4-submit.jar] [RUN_CONFIG=lab-spark]
```

The target calls `hop/run.sh` on the host. The script does these steps:

1. Checks the input. It stops with a clear message and a non-zero exit when:
   - `PIPELINE` or `PACKAGE` is empty;
   - `hop/dist/$JAR` or `hop/dist/$PACKAGE` does not exist on the host.
2. Reads the configured catalogs from the running container: the names `<name>` of the lines
   `spark.sql.catalog.<name> <value>` (no dot after the name) in
   `/opt/spark/conf/spark-defaults.conf`. The script prints only the names: the file can hold
   the Polaris client secret.
   - The container `spark` is not running: stop, tell the user to run `make up`.
   - `CATALOG` is empty and one catalog is configured: use it.
   - `CATALOG` is empty and several catalogs are configured: stop, list them, tell the user to
     set `CATALOG`.
   - `CATALOG` is empty and no catalog is configured: stop, tell the user to add a catalog to
     `COMPOSE_PROFILES`.
   - `CATALOG` is set and is not configured: stop, list the configured catalogs.
3. Writes `hop/env/hop-env.json` (Hop format), with no secret:

   ```json
   {
     "variables": [
       { "name": "LAKE_CATALOG", "value": "<catalog>",
         "description": "Spark catalog of this run, configured in spark-defaults.conf" },
       { "name": "HOP_DATA", "value": "file:///workspace/hop/out",
         "description": "Local data root for non-table outputs" }
     ]
   }
   ```

4. Runs, and exits with the exit code of `spark-submit` (Hop `MainSpark` exits non-zero when
   the pipeline fails):

   ```bash
   docker compose exec -T spark spark-submit \
     --master 'local[*]' \
     --class org.apache.hop.spark.run.MainSpark \
     "/workspace/hop/dist/$JAR" \
     --HopProjectPackage="/workspace/hop/dist/$PACKAGE" \
     --HopPipelinePath="$PIPELINE" \
     --HopRunConfigurationName="$RUN_CONFIG" \
     --HopConfigFile=/workspace/hop/env/hop-env.json
   ```

The Spark session of `spark-submit` reads the rendered `spark-defaults.conf`: Iceberg
extensions, catalogs and S3 settings. Hop reuses this session. The Spark catalog names
(`nessie`, `polaris`, `rest`) do not change. Hop pipelines use
`${LAKE_CATALOG}.<namespace>.<table>`.

Driver memory: `spark.driver.memory 4g` from `spark-defaults.conf`. On the 8 GB EC2 VM,
`trino` and `thrift` must be off during a Hop run (README).

### 4.4 Classpath

The fat jar contains `iceberg-spark-runtime` 1.11.0. The image has the same jar in
`$SPARK_HOME/jars`. Same version: expected harmless. The end-to-end trial checks it (request
R6). If a conflict occurs, the Hop side builds a fat jar without the Iceberg runtime; the lab
does not change.

## 5. Tests

### 5.1 Automated (in the repository)

- `tests/spark-image.sh`: `java -version` in the image reports version 21.
- New `tests/hop-run.sh` (needs the running stack; no Hop artifacts):
  - `PIPELINE` empty: non-zero exit, message names `PIPELINE`;
  - `PACKAGE` empty: non-zero exit, message names `PACKAGE`;
  - jar missing in `hop/dist`: non-zero exit, message names the file;
  - `CATALOG=nosuchcatalog`: non-zero exit, message lists the configured catalogs;
  - `CATALOG` empty: with one configured catalog the run uses it; with several, non-zero exit
    and the list (the test checks the case that matches the running configuration);
  - `CATALOG=<a configured catalog>` with empty dummy files in `hop/dist`: `hop-env.json` is
    valid JSON, `LAKE_CATALOG` equals the catalog, the file has no secret (no `credential`,
    no `secret` value of the Polaris settings); `spark-submit` fails on the dummy jar and the
    script exit is non-zero (exit code propagates);
  - the test removes its dummy files and `hop-env.json` at the end.
- `make lint` covers the new script (bash syntax) and the JSON files.

### 5.2 Regression on the EC2 VM (Java 21)

Run by the Claude Code session on the VM: `make lint`, `tests/spark-image.sh`,
`make smoke-test`, `tests/catalog-selection.sh`, `tests/spark-config.sh`,
`tests/trino-service.sh` (profile `trino`), then `make elt-test` for each catalog with
profile `thrift` and `trino` off (8 GB RAM).

### 5.3 End-to-end trial (user, with the Hop-side artifacts)

1. Copy the fat jar and the sample package with `scp` to `hop/dist/` on the VM.
2. Run `make hop-run` with catalog `nessie`. Read the table back with `make sql-nessie`.
3. Run it again with catalog `polaris`, with the same Hop artifacts. Read the table back with
   `make sql-polaris`.
4. Record the result, the memory use and any classpath finding in `NOTES.md`.

## 6. Documentation

- `README.md`, new section "Running Apache Hop pipelines": `scp` to `hop/dist/`,
  `make hop-run`, the choice of the catalog and `LAKE_CATALOG`, the Java 21 note, memory on
  8 GB (`trino` and `thrift` off). Add `hop-run` to the section "Make targets". Add the
  replacement procedure of section 4.1.
- `NOTES.md`: decision D19 (Java 21 image, drop zone, catalog chosen for each run) and a
  finding F11 with the results of the trial.
- `VERSIONS.md`: section 4.1.

## 7. Risks

1. Java 21 regression in Jupyter, Thrift Server, dbt or ELT. Mitigation: regression of
   section 5.2 before the PR.
2. Disk on the EC2 VM (about 11 GB free after Trino). Mitigation: the replacement procedure
   removes the Java 17 images before the build.
3. Memory on the EC2 VM (8 GB). Mitigation: `trino` and `thrift` off during a Hop run.
4. The Hop-side artifacts are not available yet. The automated tests do not need them; only
   the end-to-end trial does.

## 8. Acceptance criteria

1. `docker compose exec spark java -version` reports 21; the regression of section 5.2
   passes.
2. `tests/hop-run.sh` passes.
3. With catalog `nessie`: `make hop-run …` succeeds and the Iceberg table is visible from
   `spark-sql` in catalog `nessie`.
4. Same with catalog `polaris`, with no change to the Hop artifacts.
5. No new published port; no secret in `hop/` or in git (`make lint`).
