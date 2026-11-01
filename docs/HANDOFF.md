# Handoff — Iceberg catalog lab

- Date: 2026-11-01
- From: Claude Code session on the Linux server (Docker Engine, RustFS variant): ELT
  pipeline with dbt, Tasks 33-36 done, PR #49 open
- To: the next Claude Code session (Linux server or workstation)

## Where we are

| Item | State |
|---|---|
| Requirements | `docs/req/prompt-agente-lab-iceberg-polaris-nessie.md` (Italian) |
| Lab design spec | `docs/superpowers/specs/2026-10-28-iceberg-catalog-lab-design.md` |
| Stage 1, Phases 1-4, Nessie CLI, RustFS variant | Merged (PRs #10, #11, #16, #23, #27, #30, #32, #39) |
| Phase 5 (scenarios), Phase 6 (evaluation) | Deferred (`NOTES.md` D14) |
| **ELT with dbt** | **PR #49 open** (branch `feat/dbt-elt`, pushed, head `36b3e5c`). Not merged |
| dbt spec | `docs/superpowers/specs/2026-10-30-dbt-elt-design.md` |
| dbt plan | `docs/superpowers/plans/2026-10-30-dbt-elt.md` — Tasks 29-36, all done |
| GitHub issues | #40 … #48 all ticked, except two items of #47: "AWS regression on the EC2 VM (user)" and "DBeaver check (user)" |
| CI | The repository has no GitHub Actions workflow |

Verified by Claude on the Linux server (RustFS variant): lint, `tests/spark-image.sh`,
`tests/spark-config.sh`, `tests/compose-variant.sh`, `tests/dbt-project.sh`, and
`make elt-test` on nessie, polaris and rest (each alone and the three together). `SF=1` on
nessie passed. Final whole-branch review: clean.

User decisions of 2026-10-31 (in PR #49, `NOTES.md` F8 and `VERSIONS.md`):
- `NESSIE_MGMT_PORT` sets the Nessie management host port (issue #48).
- The `spark` image installs `git` for `dbt debug` (GPL-2.0 OS package, accepted).
- Snapshot operations of `fct_lineitem`: `overwrite` after the first build, `append` after
  the incremental merge (measured; spec and plan corrected).
- Shared S3 leftover check `tests/lib/s3-left.sh`.

## Resume here

1. The user runs the two open checks of #47 on the EC2 VM (procedure below, also in the
   comment on issue #47). The first AWS run was stopped on 2026-11-01 because it took a long
   time; no result was reported.
2. When the user reports the results:
   - All passed: tick the two items of #47. If the user gives the `time` results, add the
     AWS timings to `NOTES.md` F8 on `feat/dbt-elt` (one commit, then push).
   - A failure: fix it on `feat/dbt-elt`, batch the fixes, push once.
3. The user merges PR #49. Never merge yourself.
4. After the user confirms the merge: `git checkout main && git pull`,
   `git branch -d feat/dbt-elt`, `git push origin --delete feat/dbt-elt`,
   `rm -rf .superpowers/sdd/2026-10-30-dbt-elt`, then update this file.

## Open user checks (issue #47)

### 0. Prepare the EC2 VM

The VM is still on the deleted branch `feat/rustfs-onprem`.

```bash
git checkout main
git pull
git branch -D feat/rustfs-onprem
git fetch origin
git checkout feat/dbt-elt
git pull
```

If a test run was stopped in the middle, objects can stay under a `tpch_` prefix. Check each catalog:

```bash
make tpch-clean CATALOG=nessie
make tpch-clean CATALOG=polaris
make tpch-clean CATALOG=rest
```

The VM role can only list under `polaris/`. Delete a file that stays there from CloudShell.

### 1. AWS regression

Run one command at a time. Do not paste the commands as one block: a broken line runs `make` alone. Each test must end with `all assertions passed`. Put `time` in front of each `elt-test` to record its duration (no AWS timing exists yet; on the Linux server with RustFS: nessie ~3 min, polaris ~5 min, rest ~3 min).

```bash
tests/catalog-selection.sh
COMPOSE_PROFILES=nessie,polaris,baseline,thrift make up
COMPOSE_PROFILES=nessie,polaris,baseline,thrift make smoke-test
COMPOSE_PROFILES=nessie,polaris,baseline,thrift tests/dbt-project.sh
time COMPOSE_PROFILES=nessie,polaris,baseline,thrift make elt-test CATALOG=nessie
time COMPOSE_PROFILES=nessie,polaris,baseline,thrift make elt-test CATALOG=polaris
time COMPOSE_PROFILES=nessie,polaris,baseline,thrift make elt-test CATALOG=rest
tests/spark-config.sh
make lint
make up
```

If a test shows no progress: run `docker stats --no-stream` in a second terminal. If `spark-thrift` stays near 0% CPU for more than 5 minutes, run `docker compose restart spark-thrift` and run the test again (known stop, `NOTES.md` F8). Report it.

### 2. DBeaver check

1. Load the data and build the models:
   ```bash
   COMPOSE_PROFILES=nessie,thrift make up
   COMPOSE_PROFILES=nessie,thrift make tpch-gen SF=0.01
   COMPOSE_PROFILES=nessie,thrift make tpch-load CATALOG=nessie SF=0.01
   COMPOSE_PROFILES=nessie,thrift make dbt CATALOG=nessie ARGS=build
   ```
2. Open the SSH tunnel with `-L 10000:127.0.0.1:10000` (README, "SSH tunnel").
3. In DBeaver, create an **Apache Hive** connection: URL `jdbc:hive2://localhost:10000/;auth=noSasl`, user `spark`, no password.
4. Run `SELECT * FROM nessie.tpch_marts.revenue_by_nation`. Expected: 25 rows.
5. Change the URL to `jdbc:hive2://localhost:10000/;auth=noSasl?spark.sql.defaultCatalog=nessie` and run `SELECT * FROM tpch_marts.revenue_by_nation`. Expected: 25 rows.
6. Clean:
   ```bash
   COMPOSE_PROFILES=nessie,thrift make tpch-clean CATALOG=nessie
   make up
   ```

## State of the Linux server

- Docker Engine 29.2.1. Repository at `/home/sramazzina/work/sramazzina/iceberg-platform-poc`
  (not the plan path `/home/sramazzina/work/dev/...`).
- `.env`: RustFS variant, `NESSIE_MGMT_PORT=19000` (another stack holds host port 9000).
  Never print it.
- Remote `origin` uses SSH (`git@github.com:...`): git has no HTTPS credentials here.
- The server runs Docker stacks of other projects: touch only the project `iceberg-lab`.
- Do not modify `~/.docker/config.json` (it has a stale `ghcr.io` login).
- SDD workspace of the ELT plan: `.superpowers/sdd/2026-10-30-dbt-elt/` (ledger
  `progress.md`). Delete it after the merge.

## State of the workstation

- Windows, WSL2, Docker Desktop. RustFS variant. The spike file of issue #40 is deleted
  (2026-11-01).
- In the WSL shell `cat` is an alias for a missing `bat`: use `command cat`.

## State of the EC2 VM

- The VM is still on the deleted branch `feat/rustfs-onprem` (step 0 above fixes it).
- A stopped `make elt-test` run can have left objects under a `tpch_` prefix (step 0 above).
- The VM role can only **list** under `polaris/`: drop every Polaris table with
  `DROP TABLE ... PURGE`; a left file must be deleted by the user from CloudShell.

## Decisions already taken with the user (do not ask again)

1. Repository root = this repository. The repository is **public**: no account ID, ARN,
   bucket name, external ID, password or secret in any tracked file.
2. AWS: the user runs `aws/setup.sh` and `aws/teardown.sh` in CloudShell. Claude never
   creates or changes AWS resources.
3. Spark image `apache/spark:4.1.3-scala2.13-java17-python3-ubuntu`, Python 3.10; Iceberg
   1.11.0; versions in `VERSIONS.md`.
4. The catalogs are off by default; `COMPOSE_PROFILES` in `.env` selects them (`NOTES.md` D11).
5. Phases 5 and 6 are deferred (`NOTES.md` D14).
6. On-premise storage = RustFS 1.0.4 (Apache-2.0) through `docker-compose.rustfs.yml`.
7. ELT (2026-10-30): one generic dbt project, one target per catalog; dbt-spark `thrift`
   method through a new Spark Thrift Server (also for DBeaver); TPC-H data generated with
   DuckDB in `landing/`, loaded by PySpark into `tpch_raw`; incremental model
   `fct_lineitem` (merge). One branch, one PR for Tasks 29-36.
8. Verification: Claude verifies on the Linux server or the workstation. The user runs the AWS regression on
   the EC2 VM before the merge.
9. TPC-H data (2026-10-31): the data loads only on demand, with `make tpch-gen` and
   `make tpch-load` (script `elt/tpch_load.py`). `make up` loads nothing. Only the tests load
   a small data set (`SF=0.01`) and drop it at the end. The user confirmed this design.
10. README (2026-10-31): the user asks for operational instructions in `README.md`. Task 35
   writes them. Make sure the procedure says that the data loads only on demand, and gives
   each step as one command.

## How to execute (from `CLAUDE.md` and `~/.claude/CLAUDE.md`)

- Subagent-driven execution; do not ask for an execution mode. Implementer and fact-finding
  subagents: `model: "sonnet"`. Reviews stay with the main model.
- Commit messages, PR bodies and issues: English, Conventional Commits, **no `Co-Authored-By`
  line and no Claude attribution**.
- Do not push after every commit. Push the batch when the PR is ready; open the PR last. The
  user merges; never merge yourself. After the merge: delete the branch locally and on the
  remote, then `git checkout main && git pull`.
- Chat with the user in Italian; every file, commit, issue and PR in English (ASD-STE100).

## Rules for work in every session

- Never print `.env`, `secrets/spark_user.env` or `secrets/rustfs/spark_user.env`.
- Do not run `make reset` or `docker compose down -v` without the user's approval.
- `gh pr edit` fails (Projects classic deprecation): use
  `gh api -X PATCH repos/sramazzina/iceberg-platform-poc/pulls/<n> -F body=@<file>`.
- Use absolute paths; the shell cwd can reset between commands.

## Open points to watch

- `rustfs-setup` is verified only for a second run with the same values.
- The RustFS variant is not verified on macOS.
- Deferred: pinning of transitive pip dependencies; GPG check of the AWS CLI archive; the
  DuckDB `tpch` extension download at build time has no checksum pin (DuckDB checks its
  signature).

## Kick-off prompt for the next session

```text
Read docs/HANDOFF.md (on main). Follow "Resume here": PR #49 (dbt ELT) waits for the
user checks of issue #47.
```
