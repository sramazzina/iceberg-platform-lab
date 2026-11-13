# Apache Hop native Spark pipelines — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user run an Apache Hop pipeline with the Hop native Spark engine
(`org.apache.hop.spark.run.MainSpark`) in container `spark`, with `make hop-run`, on the
catalog that the user chooses for the run.

**Architecture:** The `spark` image moves to Java 21 (base image tag only; the Java 21 image
replaces the Java 17 image). Service `spark` mounts `./hop` on `/workspace/hop`. The host
script `hop/run.sh` checks the input, reads the configured catalog names from the rendered
`spark-defaults.conf` of the running container, writes `hop/env/hop-env.json`
(`LAKE_CATALOG`, `HOP_DATA`) and runs `spark-submit` in container `spark`.

**Tech Stack:** Docker Compose, Apache Spark 4.1.3 (Scala 2.13, Java 21), bash, jq (host),
the bash test helpers in `tests/lib/assert.sh`.

**Spec:** `docs/superpowers/specs/2026-11-13-hop-native-spark-design.md` (issue #65).

**Where:** the EC2 VM (`/home/admin/work/sramazzina/iceberg-platform-lab`), branch
`feat/hop-native-spark`. Rules of the VM (`docs/HANDOFF.md`, "State of the EC2 VM"):

- never print `.env` or `secrets/*`;
- 8 GB RAM: never run `thrift` and `trino` together; keep `trino` off during a Hop run;
- in the interactive shell `cat` is an alias for a missing `bat`: use `command cat`;
- drop every Polaris table with `DROP TABLE ... PURGE`;
- do not run `make reset` or `docker compose down -v`;
- commit after each task; do not push. The controller pushes the batch at the end.

---

## File structure

| File | Change | Responsibility |
|---|---|---|
| `.env.example` | modify | `SPARK_BASE_IMAGE` Java 21 tag |
| `VERSIONS.md` | modify | Spark and Python rows |
| `tests/spark-image.sh` | modify | Java 21 check |
| `docker-compose.yml` | modify | volume `./hop:/workspace/hop` on `spark` |
| `tests/compose-variant.sh` | modify | static check of the volume |
| `.gitignore` | modify | content of `hop/dist`, `hop/env`, `hop/out` |
| `hop/dist/.gitkeep`, `hop/env/.gitkeep`, `hop/out/.gitkeep` | create | keep the folders |
| `hop/run.sh` | create | input checks, catalog choice, `hop-env.json`, `spark-submit` |
| `Makefile` | modify | target `hop-run` |
| `tests/hop-run.sh` | create | checks of `hop/run.sh` and `make hop-run` without Hop artifacts |
| `README.md` | modify | section "Running Apache Hop pipelines", make target, Java 21 replacement |
| `NOTES.md` | modify (on `main`, see Task 4) | D19, F11 |

---

### Task 1: Java 21 image (issue #66)

**Files:**
- Modify: `tests/spark-image.sh` (after the line `echo "spark image"`)
- Modify: `.env.example:74`
- Modify: `VERSIONS.md:11`, `VERSIONS.md:25`
- Modify: `.env` on the VM (not tracked; never print it)

- [ ] **Step 1: Verify that the base image tag exists**

Run: `docker buildx imagetools inspect apache/spark:4.1.3-scala2.13-java21-python3-ubuntu | head -n 20`
Expected: a manifest list with `linux/amd64` (and `linux/arm64`). If the tag does not exist,
STOP and report to the controller.

- [ ] **Step 2: Write the failing test**

In `tests/spark-image.sh`, after the line `echo "spark image"`, add:

```bash
# Apache Hop native Spark needs Java 21 (spec 2026-11-13-hop-native-spark-design, 4.1).
assert_contains "$(run bash -c 'java -version 2>&1 | head -n1')" 'version "21' "Java 21"
```

- [ ] **Step 3: Run the test to verify that it fails**

Run: `tests/spark-image.sh`
Expected: `FAIL - Java 21 (missing 'version "21')`; the other assertions pass.

- [ ] **Step 4: Change the tag in `.env.example` and `VERSIONS.md`**

`.env.example` line 74:

```text
SPARK_BASE_IMAGE=apache/spark:4.1.3-scala2.13-java21-python3-ubuntu
```

`VERSIONS.md` line 11:

```text
| Apache Spark | 4.1.3 (Scala 2.13, Java 21) | `SPARK_BASE_IMAGE=apache/spark:4.1.3-scala2.13-java21-python3-ubuntu` | <https://hub.docker.com/r/apache/spark/tags>, <https://github.com/apache/spark-docker/tree/master/4.1.3/scala2.13-java21-python3-ubuntu> |
```

`VERSIONS.md` line 25: replace `scala2.13-java17-python3-ubuntu` with
`scala2.13-java21-python3-ubuntu` in the URL. Leave line 64 (Nessie CLI, checked on Java 17)
as it is; Task 3 records the Java 21 result.

- [ ] **Step 5: Replace the image on the VM (Java 17 image removed before the build)**

Run each command separately:

```bash
docker compose rm -sf spark spark-thrift
docker image rm iceberg-lab-spark:1.11.0
docker image rm apache/spark:4.1.3-scala2.13-java17-python3-ubuntu
sed -i 's|^SPARK_BASE_IMAGE=.*|SPARK_BASE_IMAGE=apache/spark:4.1.3-scala2.13-java21-python3-ubuntu|' .env
grep -c '^SPARK_BASE_IMAGE=apache/spark:4.1.3-scala2.13-java21-python3-ubuntu$' .env
make up
```

Expected: `grep -c` prints `1`; `make up` builds the image and all services are healthy.
If `.env` has no `SPARK_BASE_IMAGE` line (`grep -c` prints `0`), the value comes from
somewhere else: STOP and report. Do not print `.env`.

- [ ] **Step 6: Check the Ubuntu and Python versions of the new image**

Run: `docker compose exec -T spark bash -c 'grep VERSION_ID /etc/os-release; python3 --version'`
Expected: `VERSION_ID="22.04"` and `Python 3.10.x` (as in the Java 17 image). If they differ,
STOP and report to the controller: the pip pins of `spark/requirements.txt` and issue #52 are
affected.

- [ ] **Step 7: Run the test to verify that it passes**

Run: `tests/spark-image.sh`
Expected: `all assertions passed`, including `ok   - Java 21`.

- [ ] **Step 8: Remove dangling images and check the disk**

Run: `docker image prune -f`
Run: `df -h /`
Expected: no error; report the free space to the controller.

- [ ] **Step 9: Commit**

```bash
git add tests/spark-image.sh .env.example VERSIONS.md
git commit -m "feat(spark): move the Spark image to Java 21 (#66)"
```

---

### Task 2: Drop zone and `make hop-run` (issue #67)

**Files:**
- Modify: `docker-compose.yml` (service `spark`, `volumes`)
- Modify: `tests/compose-variant.sh` (section `compose variant: AWS stack`)
- Modify: `.gitignore`
- Create: `hop/dist/.gitkeep`, `hop/env/.gitkeep`, `hop/out/.gitkeep`
- Create: `hop/run.sh`
- Modify: `Makefile`
- Create: `tests/hop-run.sh`

- [ ] **Step 1: Write the failing static test of the volume**

In `tests/compose-variant.sh`, after the line
`assert_eq "$(src "$aws" rest-fixture /home/iceberg)" "rest-fixture-data" "rest catalog on the volume rest-fixture-data"`
(the AWS section), add:

```bash
assert_eq "$(src "$aws" spark /workspace/hop)" "$ROOT/hop" "spark mounts ./hop on /workspace/hop"
assert_eq "$(src "$aws" spark-thrift /workspace/hop)" "" "spark-thrift does not mount ./hop"
```

- [ ] **Step 2: Run it to verify that it fails**

Run: `tests/compose-variant.sh`
Expected: `FAIL - spark mounts ./hop on /workspace/hop (expected '<root>/hop', got '')`.

- [ ] **Step 3: Add the volume, the folders and the ignore rules**

In `docker-compose.yml`, service `spark`, at the end of `volumes` (after
`- ./dbt:/workspace/dbt`), add:

```yaml
      # Apache Hop native Spark (spec 2026-11-13-hop-native-spark-design): fat jars and
      # project packages in dist/, hop-env.json in env/, outputs in out/.
      - ./hop:/workspace/hop
```

Create the empty files `hop/dist/.gitkeep`, `hop/env/.gitkeep`, `hop/out/.gitkeep`.

At the end of `.gitignore`, add:

```text
/hop/dist/*
!/hop/dist/.gitkeep
/hop/env/*
!/hop/env/.gitkeep
/hop/out/*
!/hop/out/.gitkeep
```

- [ ] **Step 4: Run the static test to verify that it passes**

Run: `tests/compose-variant.sh`
Expected: `all assertions passed`.

- [ ] **Step 5: Write the failing test of `hop/run.sh`**

Create `tests/hop-run.sh` (mode 755):

```bash
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
```

- [ ] **Step 6: Run it to verify that it fails**

Run: `tests/hop-run.sh`
Expected: failures, with `hop/run.sh: No such file or directory` in the messages.

- [ ] **Step 7: Write `hop/run.sh`**

Create `hop/run.sh` (mode 755):

```bash
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
```

- [ ] **Step 8: Add the make target**

In `Makefile`, add `hop-run` at the end of the `.PHONY` line. At the end of the file, add:

```make

# Apache Hop native Spark (spec 2026-11-13-hop-native-spark-design). The Hop artifacts are
# in hop/dist/. CATALOG is optional when only one catalog is configured.
hop-run:
	PIPELINE="$(PIPELINE)" PACKAGE="$(PACKAGE)" CATALOG="$(CATALOG)" JAR="$(JAR)" RUN_CONFIG="$(RUN_CONFIG)" hop/run.sh
```

- [ ] **Step 9: Recreate `spark` with the new volume**

Run: `make up`
Expected: `spark` is recreated and healthy.

- [ ] **Step 10: Run the tests to verify that they pass**

Run: `tests/hop-run.sh`
Expected: `all assertions passed`. On the VM with profiles `nessie,polaris,baseline`, the
"several catalogs" branch runs.

Run: `make lint`
Expected: `lint passed`, `no secrets found`, and `all assertions passed` for
`tests/compose-variant.sh`.

Run: `git status --short hop`
Expected: only `hop/run.sh` and the three `.gitkeep` files are untracked (no `hop-env.json`).

- [ ] **Step 11: Commit**

```bash
git add docker-compose.yml tests/compose-variant.sh .gitignore hop/run.sh hop/dist/.gitkeep hop/env/.gitkeep hop/out/.gitkeep Makefile tests/hop-run.sh
git commit -m "feat(hop): add the hop drop zone and make hop-run (#67)"
```

---

### Task 3: Regression on Java 21 (issue #68)

No code change. The EC2 VM has 8 GB: follow the order of the steps. Record each result
(pass or fail, duration) for Task 4.

**Files:** none (results go to `NOTES.md` in Task 4).

- [ ] **Step 1: Static checks**

Run: `make lint`
Expected: `lint passed`, `no secrets found`, `all assertions passed`.

- [ ] **Step 2: Base stack and catalogs (profiles `nessie,polaris,baseline`)**

Run each test separately:

```bash
tests/spark-image.sh
make smoke-test
tests/catalog-selection.sh
tests/spark-config.sh
```

Expected: each one ends with `all assertions passed` (or the success line of the script).

- [ ] **Step 3: Trino**

Run: `COMPOSE_PROFILES=nessie,polaris,baseline,trino make up`
Run: `COMPOSE_PROFILES=nessie,polaris,baseline,trino tests/trino-service.sh`
Expected: `all assertions passed`.

- [ ] **Step 4: Thrift Server and ELT (`trino` off)**

Run: `COMPOSE_PROFILES=nessie,polaris,baseline,thrift make up`
Expected: `trino` stops; `spark-thrift` is healthy.

Run each command separately:

```bash
COMPOSE_PROFILES=nessie,polaris,baseline,thrift tests/thrift-service.sh
COMPOSE_PROFILES=nessie,polaris,baseline,thrift make elt-test CATALOG=nessie
COMPOSE_PROFILES=nessie,polaris,baseline,thrift make elt-test CATALOG=polaris
COMPOSE_PROFILES=nessie,polaris,baseline,thrift make elt-test CATALOG=rest
```

Expected: each one passes. Compare the durations with `NOTES.md` F8.

- [ ] **Step 5: Nessie CLI on Java 21**

Run: `docker compose exec -T spark nessie --version`
Expected: `0.109.0`.

- [ ] **Step 6: Restore the profiles of the VM**

Run: `make up`
Expected: the profiles of `.env` (`nessie,polaris,baseline,trino`) run again; `thrift` stops.

- [ ] **Step 7: Report**

Report to the controller: each result, the durations, any failure with its output. Do not
commit (no file changed).

---

### Task 4: Documentation (issue #69)

**Files:**
- Modify: `README.md` (section "Make targets"; new section "Running Apache Hop pipelines"
  before "On-premise with RustFS"; table "Documents" if it lists specs)
- Not in this branch: `NOTES.md`. The user rule: `NOTES.md` is committed directly to `main`.
  This task reports the D19 text; the controller commits it on `main` (Step 5).

- [ ] **Step 1: Add the make target row**

In `README.md`, section "Make targets", after the row of `make elt-test`, add:

```text
| `make hop-run PIPELINE=<p> PACKAGE=<zip> [CATALOG=<c>] [JAR=<jar>] [RUN_CONFIG=<r>]` | Runs an Apache Hop pipeline with the Hop native Spark engine in `spark` (see [Running Apache Hop pipelines](#running-apache-hop-pipelines)) |
```

- [ ] **Step 2: Add the section "Running Apache Hop pipelines"**

In `README.md`, before `## On-premise with RustFS`, add:

````markdown
## Running Apache Hop pipelines

Apache Hop runs on your PC. The lab runs a Hop pipeline with the Hop native Spark engine in
the container `spark` (`local[*]`). The Spark session reads the lab configuration: Iceberg
extensions, the catalogs that are on and the S3 settings.

The `spark` image uses Java 21: Hop needs it.

### Prepare the Hop artifacts (on your PC)

The Hop side gives two files:

- the fat jar, built with `hop-conf.sh --generate-fat-jar=... --spark-client-version=native-provided`
  (default name `hop-native-spark4-submit.jar`);
- the project package (`.zip`), built with `hop-conf.sh --export-spark-project=...`.

In the pipelines, use `${LAKE_CATALOG}.<namespace>.<table>` for Iceberg tables. Leave the
field "catalog metadata" of the Lake Table transforms empty. Leave the Spark master of the
run configuration empty.

### Copy the artifacts to the lab

On a remote VM, copy the files to `hop/dist/` with `scp` (same key and host as the
[SSH tunnel](#ssh-tunnel)):

```bash
scp hop-native-spark4-submit.jar project.zip <user>@<vm>:<lab directory>/hop/dist/
```

On a local host, copy the files to `hop/dist/`.

### Run a pipeline

1. Run `make up`. On the VM with 8 GB, keep `trino` and `thrift` off during a Hop run (see
   [Memory per service](#memory-per-service)).
2. Run `make hop-run PIPELINE=pipelines/my-pipeline.hpl PACKAGE=project.zip`.
   - With one catalog on, the run uses it.
   - With several catalogs on, add `CATALOG=nessie`, `CATALOG=polaris` or `CATALOG=rest`.
3. Read the result with `make sql-nessie`, `make sql-polaris` or `make sql-rest`.

`make hop-run` writes `hop/env/hop-env.json` with the Hop variables `LAKE_CATALOG` (the
catalog of the run) and `HOP_DATA` (`file:///workspace/hop/out`). The file has no secret.
The exit code is the exit code of the pipeline.

### Move an existing host to the Java 21 image

The Java 21 image replaces the Java 17 image. Run each command separately:

1. `docker compose rm -sf spark spark-thrift`
2. `docker image rm iceberg-lab-spark:1.11.0`
3. `docker image rm apache/spark:4.1.3-scala2.13-java17-python3-ubuntu`
4. In `.env`, set
   `SPARK_BASE_IMAGE=apache/spark:4.1.3-scala2.13-java21-python3-ubuntu`.
5. `make up`
````

- [ ] **Step 3: Check the README links and lint**

Run: `grep -n '#running-apache-hop-pipelines\|#memory-per-service\|#ssh-tunnel' README.md`
Expected: the anchors match the headings `## Running Apache Hop pipelines`,
`### Memory per service`, `### SSH tunnel`.

Run: `make lint`
Expected: `lint passed`.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs(readme): document make hop-run and the Java 21 image (#69)"
```

- [ ] **Step 5: Report the D19 text**

Report to the controller this text for `NOTES.md` (the controller commits it on `main`):

```markdown
### D19 — Apache Hop native Spark: Java 21, drop zone, catalog chosen for each run
- Requirement: issue #65 (request `docs/lab-adaptation-for-hop-native-spark.md`).
- Lab: the `spark` image uses Java 21 (`apache/spark:4.1.3-scala2.13-java21-python3-ubuntu`);
  the Java 21 image replaces the Java 17 image. Service `spark` mounts `./hop` on
  `/workspace/hop`. `make hop-run` (script `hop/run.sh`) writes `hop/env/hop-env.json` with
  `LAKE_CATALOG` for each run: `CATALOG=`, or the only configured catalog. The catalog names
  come from the rendered `spark-defaults.conf`. Upload with `scp` only.
- Why: Hop is compiled for Java 21. The user wants the catalogs to be mutually exclusive, but
  the lab does not enforce it; a choice for each run works in both cases. S3/SSM upload and a
  driver memory parameter are deferred.
- Spec: `docs/superpowers/specs/2026-11-13-hop-native-spark-design.md`. Finding: F11.
```

---

### Task 5: End-to-end trial with the Hop artifacts (issue #70)

The user gives the Hop artifacts (spec section 5.3). The controller guides the user and runs
the commands on the VM. Profiles: `nessie,polaris,baseline` (`trino` and `thrift` off).

**Files:** none in the branch. F11 goes to `NOTES.md` on `main` (controller).

- [ ] **Step 1: Check the artifacts**

Run: `ls -l hop/dist/`
Expected: the fat jar and the project package, owned by the host user.

- [ ] **Step 2: Run with catalog `nessie`**

Run: `COMPOSE_PROFILES=nessie,polaris,baseline make up`
Run: `make hop-run PIPELINE=<pipeline of the sample> PACKAGE=<package> CATALOG=nessie`
Expected: exit 0. In another shell, run `docker stats --no-stream` during the run and record
the memory of `spark`.

- [ ] **Step 3: Read the table back from `nessie`**

Run: `docker compose exec -T spark spark-sql -S -e "SELECT count(*) FROM nessie.<namespace>.<table>" </dev/null`
Expected: the row count that the sample pipeline writes.

- [ ] **Step 4: Run with catalog `polaris` (same artifacts)**

Run: `make hop-run PIPELINE=<pipeline of the sample> PACKAGE=<package> CATALOG=polaris`
Run: `docker compose exec -T spark spark-sql -S -e "SELECT count(*) FROM polaris.<namespace>.<table>" </dev/null`
Expected: exit 0 and the same row count.

- [ ] **Step 5: Check the classpath (request R6)**

Run: `docker compose exec -T spark bash -c 'ls "$SPARK_HOME/jars" | grep iceberg'`
Expected: `iceberg-spark-runtime-4.1_2.13-1.11.0.jar` and `iceberg-aws-bundle-1.11.0.jar`.
Read the output of the runs for `NoSuchMethodError`, `ClassCastException` or
`LinkageError`. Record the result.

- [ ] **Step 6: Clean up**

Drop the test tables: `DROP TABLE nessie.<namespace>.<table>` and
`DROP TABLE polaris.<namespace>.<table> PURGE` (the VM role can only list under `polaris/`).

- [ ] **Step 7: Report**

Report the results (exit codes, row counts, memory, classpath) for `NOTES.md` F11.

---

## Order and end of the work

1. Tasks 1 and 2 (commits on `feat/hop-native-spark`), review after each task.
2. Task 3 (regression). Task 4 (README commit).
3. Final review of the branch. Push the batch once. Open the PR with `Closes #66`,
   `Closes #67`, `Closes #68`, `Closes #69`. Tick the checklists before the PR.
4. Task 5 when the user has the Hop artifacts (before or after the merge). Close #70 and #65
   when the trial passes.
5. `NOTES.md` D19 (after Task 4) and F11 (after Task 5) on `main`; `docs/HANDOFF.md` on
   `main`.
