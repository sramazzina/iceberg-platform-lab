# CLAUDE.md

Iceberg platform lab: a reproducible Docker Compose lab to evaluate and compare the Apache Iceberg REST catalogs Apache Polaris and Project Nessie (with Spark, Trino, dbt and Hop), on an EC2 VM with AWS S3 or on-premise with RustFS. It is a test environment, not production. Usage is in `README.md`.

## Git workflow

- Changes to the lab (Compose files, service directories, `aws/`, `elt/`, `scenarios/`, `tests/`, `Makefile`) go on a branch and reach `main` through a PR. The user merges.
- Documentation (`docs/`, `NOTES.md`, `README.md`, `VERSIONS.md`) may be committed directly on `main`.
- No AI attribution (`Co-Authored-By` trailers or similar) in commits, PRs, issues or PR/issue comments.

## Notes

- Record deviations and decisions in `NOTES.md` as `Dnn`, findings as `Fnn`, with the next free number.
