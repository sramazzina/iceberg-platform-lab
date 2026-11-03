# Handoff — Iceberg catalog lab

- Date: 2026-11-03
- From: Claude Code session on the Linux server (Docker Engine, RustFS variant): user checks
  of issue #47 (AWS regression and DBeaver), fixes on PR #49
- To: the next Claude Code session (Linux server or workstation)

## Where we are

| Item | State |
|---|---|
| Requirements | `docs/req/prompt-agente-lab-iceberg-polaris-nessie.md` (Italian) |
| Lab design spec | `docs/superpowers/specs/2026-10-28-iceberg-catalog-lab-design.md` |
| Stage 1, Phases 1-4, Nessie CLI, RustFS variant | Merged (PRs #10, #11, #16, #23, #27, #30, #32, #39) |
| Phase 5 (scenarios), Phase 6 (evaluation) | Deferred (`NOTES.md` D14) |
| **ELT with dbt** | **PR #49 open, ready for the merge** (branch `feat/dbt-elt`, pushed, head `0507a1d`). Not merged |
| dbt spec | `docs/superpowers/specs/2026-10-30-dbt-elt-design.md` |
| dbt plan | `docs/superpowers/plans/2026-10-30-dbt-elt.md` — Tasks 29-36, all done |
| GitHub issues | #40 … #48 all ticked (#47 included). #50 open (analysis, next session) |
| CI | The repository has no GitHub Actions workflow |

Checks of 2026-11-03:
- AWS regression on the EC2 VM (user): all tests passed. `make elt-test` timings: nessie
  6 min 55 s, polaris 9 min 32 s, rest 7 min 40 s (`NOTES.md` F8).
- DBeaver on the EC2 VM through the SSH tunnel (user): three-part name and the URL with
  `spark.sql.defaultCatalog` both return 25 rows.
- Linux server (Claude): `make lint`, `tests/thrift-service.sh` with an open stdin, and
  `make elt-test` on nessie, polaris and rest with the new check passed.

Fixes on `feat/dbt-elt` (2026-11-03):
- `c671a0f`: beeline with `-e` waits for input when its stdin stays open, and
  `docker compose exec -T` forwards the stdin of the terminal. The AWS run stopped for hours in
  `tests/thrift-service.sh`. Every beeline call reads stdin from `/dev/null` (`NOTES.md` F8).
- `24e0b0c`: AWS timings in `NOTES.md` F8.
- `0507a1d`: README, DBeaver section. The navigator shows only the schemas of the Spark session
  catalog, not the Iceberg tables. The URL with a default catalog needs `;` in front of `?`
  (`jdbc:hive2://localhost:10000/;auth=noSasl;?spark.sql.defaultCatalog=nessie`); without it
  the driver ignores `auth=noSasl`. `tests/elt.sh` checks that URL.

## Resume here

1. The user merges PR #49. Never merge yourself.
2. After the user confirms the merge: `git checkout main && git pull`,
   `git branch -d feat/dbt-elt`, `git push origin --delete feat/dbt-elt`,
   `rm -rf .superpowers/sdd/2026-10-30-dbt-elt`, then update this file.
3. Next goal proposed by the user: issue #50, analysis of how the DBeaver navigator can show
   the Iceberg catalogs. Analysis only; agree the approach with the user before any change.
   Brainstorm with `superpowers:brainstorming`.

## State of the Linux server

- Docker Engine 29.2.1. Repository at `/home/sramazzina/work/sramazzina/iceberg-platform-poc`
  (not the plan path `/home/sramazzina/work/dev/...`).
- `.env`: RustFS variant, `NESSIE_MGMT_PORT=19000` (another stack holds host port 9000).
  Never print it. The stack runs with the `.env` selection (no catalog).
- Remote `origin` uses SSH (`git@github.com:...`): git has no HTTPS credentials here.
- The server runs Docker stacks of other projects: touch only the project `iceberg-lab`.
- Do not modify `~/.docker/config.json` (it has a stale `ghcr.io` login).
- SDD workspace of the ELT plan: `.superpowers/sdd/2026-10-30-dbt-elt/` (ledger
  `progress.md`). Delete it after the merge.

## State of the workstation

- Windows, WSL2, Docker Desktop. RustFS variant.
- In the WSL shell `cat` is an alias for a missing `bat`: use `command cat`.

## State of the EC2 VM

- On branch `feat/dbt-elt`. After the merge: `git checkout main && git pull`, then
  `git branch -D feat/dbt-elt`.
- The stack runs with the `.env` selection. No `tpch_` data is left (cleaned by the user).
- The files `thrift-dump.txt` and `beeline-dump.txt` (thread dumps of the debug session) can
  be in the repository directory, untracked. The user can delete them.
- The VM role can only **list** under `polaris/`: drop every Polaris table with
  `DROP TABLE ... PURGE`; a left file must be deleted by the user from CloudShell.
- SSH tunnel from Windows: the key file must be readable only by the user (`icacls … /inheritance:r`,
  then `/grant:r "$(whoami):(R)"`). The README on `main` lacks `-L 10000:...` until PR #49 is
  merged.

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
8. Verification: Claude verifies on the Linux server or the workstation. The user runs the
   AWS regression on the EC2 VM before the merge.
9. TPC-H data (2026-10-31): the data loads only on demand, with `make tpch-gen` and
   `make tpch-load`. `make up` loads nothing. Only the tests load a small data set
   (`SF=0.01`) and drop it at the end.
10. README (2026-10-31): operational instructions in `README.md`, each step as one command.

## How to execute (from `CLAUDE.md` and `~/.claude/CLAUDE.md`)

- Subagent-driven execution; do not ask for an execution mode. Implementer and fact-finding
  subagents: `model: "sonnet"`. Reviews stay with the main model.
- Commit messages, PR bodies and issues: English, Conventional Commits, **no `Co-Authored-By`
  line and no Claude attribution**.
- Do not push after every commit. Push the batch when the PR is ready; open the PR last. The
  user merges; never merge yourself.
- Chat with the user in Italian; every file, commit, issue and PR in English (ASD-STE100).

## Rules for work in every session

- Never print `.env`, `secrets/spark_user.env` or `secrets/rustfs/spark_user.env`.
- Do not run `make reset` or `docker compose down -v` without the user's approval.
- `gh pr edit` fails (Projects classic deprecation): use
  `gh api -X PATCH repos/sramazzina/iceberg-platform-poc/pulls/<n> -F body=@<file>`.
- Use absolute paths; the shell cwd can reset between commands.
- Commands for the user: one command per code block, short lines. Long lines break when
  pasted, and `make` then runs its default target (`lint`). For a series of `make` commands
  with the same profiles, tell the user to `export COMPOSE_PROFILES=...` once.
- Every `make tpch-*` and `make dbt` command needs the catalog in `COMPOSE_PROFILES`.

## Open points to watch

- Issue #50: DBeaver navigator and the Iceberg catalogs (analysis).
- Issue #47 has a comment with the old procedure (step 0 without `COMPOSE_PROFILES`). An edit
  of the comment was blocked by the permission mode; the procedure is no longer needed.
- `rustfs-setup` is verified only for a second run with the same values.
- The RustFS variant is not verified on macOS.
- Deferred: pinning of transitive pip dependencies; GPG check of the AWS CLI archive; the
  DuckDB `tpch` extension download at build time has no checksum pin (DuckDB checks its
  signature).

## Kick-off prompt for the next session

```text
Read docs/HANDOFF.md (on main). Follow "Resume here": PR #49 (dbt ELT) is ready for the
merge; then issue #50 (DBeaver navigator analysis).
```
