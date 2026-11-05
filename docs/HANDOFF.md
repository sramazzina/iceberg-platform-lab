# Handoff — Iceberg catalog lab

- Date: 2026-11-05
- From: Claude Code session on the workstation (WSL2, Docker Desktop, RustFS variant):
  local setup for study, repository rename, issue #52
- To: the next Claude Code session (Linux server, workstation or EC2 VM)

## Where we are

| Item | State |
|---|---|
| Requirements | `docs/req/prompt-agente-lab-iceberg-polaris-nessie.md` (Italian) |
| Lab design spec | `docs/superpowers/specs/2026-10-28-iceberg-catalog-lab-design.md` |
| Stage 1, Phases 1-4, Nessie CLI, RustFS variant, ELT with dbt | Merged (PRs #10, #11, #16, #23, #27, #30, #32, #39, #49) |
| Phase 5 (scenarios), Phase 6 (evaluation) | Deferred (`NOTES.md` D14) |
| ELT with dbt | Merged (PR #49, merge commit `72b81ca`, 2026-11-03). Branch `feat/dbt-elt` deleted (local and remote); SDD workspace deleted |
| dbt spec | `docs/superpowers/specs/2026-10-30-dbt-elt-design.md` |
| dbt plan | `docs/superpowers/plans/2026-10-30-dbt-elt.md` — Tasks 29-36, all done |
| GitHub issues | #40 … #48 closed, all checklists ticked. #50 open (analysis). #51 open (low priority). #52 open (Python upgrade) |
| Repository name | `sramazzina/iceberg-platform-lab` since 2026-11-05 (was `iceberg-platform-poc`; GitHub redirects the old name) |
| CI | The repository has no GitHub Actions workflow |

Checks of 2026-11-03:
- AWS regression on the EC2 VM (user): all tests passed. `make elt-test` timings: nessie
  6 min 55 s, polaris 9 min 32 s, rest 7 min 40 s (`NOTES.md` F8).
- DBeaver on the EC2 VM through the SSH tunnel (user): three-part name and the URL with
  `spark.sql.defaultCatalog` both return 25 rows.
- Linux server (Claude): `make lint`, `tests/thrift-service.sh` with an open stdin, and
  `make elt-test` on nessie, polaris and rest with the new check passed.

Fixes of 2026-11-03 (in PR #49):
- `c671a0f`: beeline with `-e` waits for input when its stdin stays open, and
  `docker compose exec -T` forwards the stdin of the terminal. The AWS run stopped for hours in
  `tests/thrift-service.sh`. Every beeline call reads stdin from `/dev/null` (`NOTES.md` F8).
- `24e0b0c`: AWS timings in `NOTES.md` F8.
- `0507a1d`: README, DBeaver section. The navigator shows only the schemas of the Spark session
  catalog, not the Iceberg tables. The URL with a default catalog needs `;` in front of `?`
  (`jdbc:hive2://localhost:10000/;auth=noSasl;?spark.sql.defaultCatalog=nessie`); without it
  the driver ignores `auth=noSasl`. `tests/elt.sh` checks that URL.

Changes of 2026-11-05 (workstation):
- The user renamed the GitHub repository to `iceberg-platform-lab`. Commit `35453c8` (on
  `main`) replaces every reference in the tracked files. The workstation clone has the new
  remote URL and the new directory name.
- Issue #52 (`priority: medium`): the `spark` image has only Python 3.10.12 (Ubuntu 22.04
  package). Python 3.10 reached its end of life in October 2026 (PEP 619). Found by the agent
  that creates the dbt skeleton project.
- The user creates a separate dbt skeleton project for exercises on the lab: repository
  `sramazzina/dbt-lab-iceberg` (public). It connects through the Spark Thrift Server
  (`localhost:10000`, `auth: NOSASL`, `set:hiveconf:spark.sql.defaultCatalog`). It is not
  part of this repository.

## Resume here

0. On every machine with an old clone (Linux server, EC2 VM), do the rename steps in
   "Rename of the clone" below before any other work.
1. No work is in progress.
2. Next goal proposed by the user: issue #50, analysis of how the DBeaver navigator can show
   the Iceberg catalogs. Analysis only; agree the approach with the user before any change.
   Brainstorm with `superpowers:brainstorming`.

## State of the Linux server

- Docker Engine 29.2.1. Repository at `/home/sramazzina/work/sramazzina/iceberg-platform-poc`
  (not the plan path `/home/sramazzina/work/dev/...`). Rename to `iceberg-platform-lab` is
  pending (see "Rename of the clone").
- `.env`: RustFS variant, `NESSIE_MGMT_PORT=19000` (another stack holds host port 9000).
  Never print it. The stack runs with the `.env` selection (no catalog).
- Remote `origin` uses SSH (`git@github.com:...`): git has no HTTPS credentials here.
- The server runs Docker stacks of other projects: touch only the project `iceberg-lab`.
- Do not modify `~/.docker/config.json` (it has a stale `ghcr.io` login).

## State of the workstation

- Windows, WSL2, Docker Desktop 29.9.2. RustFS variant. Python 3.13.5 on the WSL host.
- Repository at `/home/sramazzina/work/dev/sramazzina/iceberg-platform-lab` (renamed
  2026-11-05; remote updated; Serena config updated).
- In the WSL shell `cat` is an alias for a missing `bat`: use `command cat`.
- Used by the user for study from 2026-11-05. `.env`: `COMPOSE_PROFILES=nessie,thrift`.
  The stack runs. The user keeps `thrift` on: this machine has only one user.
- Nessie has the namespace `default` (needed by dbt and by JDBC clients with a default
  catalog) and a left namespace `smoke`.

## Rename of the clone

Do these steps on each machine with a clone from before 2026-11-05. The containers bind-mount
the absolute path of the directory, so the stack must stop before the rename.

1. In the old directory, run `make down` (it keeps the volumes; not `make reset`).
2. Rename the directory from `iceberg-platform-poc` to `iceberg-platform-lab`.
3. In the new directory, run
   `git remote set-url origin git@github.com:sramazzina/iceberg-platform-lab.git`.
4. Run `git pull`.
5. Run `make up`.
6. If Serena is used: update `project_name` in `.serena/project.yml` and the project path in
   `~/.serena/serena_config.yml`.

## State of the EC2 VM

- On `main` at 2026-11-03; branch `feat/dbt-elt` deleted. Rename to `iceberg-platform-lab`
  is pending (see "Rename of the clone").
- The stack runs with the `.env` selection. No `tpch_` data is left (cleaned by the user).
- The VM role can only **list** under `polaris/`: drop every Polaris table with
  `DROP TABLE ... PURGE`; a left file must be deleted by the user from CloudShell.
- SSH tunnel from Windows: the key file must be readable only by the user (`icacls … /inheritance:r`,
  then `/grant:r "$(whoami):(R)"`). The tunnel command of the README includes `-L 10000:...`.

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
- Labels of new issues (created 2026-11-03): one `priority: high|medium|low`; the type
  (`bug`, `enhancement`, `documentation` or `analysis`); one or more `area: catalogs|storage|
  spark|elt|aws|release`; `needs: user` when the issue waits for a check of the user;
  `blocked` when it cannot continue.

## Rules for work in every session

- Never print `.env`, `secrets/spark_user.env` or `secrets/rustfs/spark_user.env`.
- Do not run `make reset` or `docker compose down -v` without the user's approval.
- `gh pr edit` fails (Projects classic deprecation): use
  `gh api -X PATCH repos/sramazzina/iceberg-platform-lab/pulls/<n> -F body=@<file>`.
- Use absolute paths; the shell cwd can reset between commands.
- Commands for the user: one command per code block, short lines. Long lines break when
  pasted, and `make` then runs its default target (`lint`). For a series of `make` commands
  with the same profiles, tell the user to `export COMPOSE_PROFILES=...` once.
- Every `make tpch-*` and `make dbt` command needs the catalog in `COMPOSE_PROFILES`.

## Open points to watch

- Issue #50: DBeaver navigator and the Iceberg catalogs (analysis).
- Issue #52 (medium priority): upgrade the Python runtime of the `spark` image (Python 3.10
  end of life). Not started. The checklist is in the issue.
- Issue #51 (low priority): analysis of a distributable release. Findings of the brainstorming
  of 2026-11-03 and the licence inventory of the `spark` image are in the issue. Decision of
  2026-11-03: no release for now (internal use by the user and the team); keep `git` in the image.
- Issue #47 has a comment with the old procedure (step 0 without `COMPOSE_PROFILES`). An edit
  of the comment was blocked by the permission mode; the procedure is no longer needed.
- `rustfs-setup` is verified only for a second run with the same values.
- The RustFS variant is not verified on macOS.
- Deferred: pinning of transitive pip dependencies; GPG check of the AWS CLI archive; the
  DuckDB `tpch` extension download at build time has no checksum pin (DuckDB checks its
  signature).

## Kick-off prompt for the next session

```text
Read docs/HANDOFF.md (on main). The repository is now iceberg-platform-lab. Follow
"Resume here": rename the old clone if needed, then issue #50 (DBeaver navigator analysis)
or issue #52 (Python upgrade).
```
