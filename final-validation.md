# Final local validation — patient-db Liquibase

Result: **PASS**, all nine executions; no code or applied migration changes required.
Executed 2026-11-03, 11:30:06–11:43:40 America/Bogota (16:30:06–16:43:40 UTC).
Refs: [DB issue #1](https://github.com/code-corhuila/dlc-patient-db/issues/1),
[acceptance matrix](acceptance-evidence.md). This is local technical evidence, not reviewer approval.

## Validated revision and environment

DB HEAD: `4297e928f6fecbf11edf75fbddf4afc3a7500a67`, branch
`chore/patient-db-acceptance-evidence`. The initial working tree contained only
README, readiness, PR-template and acceptance-evidence documentation changes.
The manifest records that diff, the untracked document snapshot and SHA-256 values
of every tracked/untracked source file; all stayed unchanged during execution.
This report and the evidence links were added after execution; executable files
remain identical to HEAD. Record the final documentation commit SHA in the PR.

Docs baseline: `31fb316d8209fbf1838feea9ecf0192c4b551585`; the three existing
uncommitted search drafts were left untouched, as disclosed in readiness.
Python 3.12.14; Docker Desktop 4.60.1, Linux Engine 29.2.0;
PostgreSQL `16.6-alpine`; Liquibase `4.29.2` (configured container images).
Tests ran sequentially against disposable databases with synthetic credentials/data.

## Executed commands and results

Every command used `python -B`; elapsed times below include process startup.

| Check | Arguments | Seconds | Exit |
|---|---|---:|---:|
| Rollback regression: six unit tests | `-m unittest discover -s tooling -p test_rollback_verification.py -v` | 0.407 | 0 |
| Full migration suite | `tooling/verify_migrations.py` | 312.672 | 0 |
| Environment dev | `tooling/verify_migrations.py --environment=dev` | 74.406 | 0 |
| Environment qa | `tooling/verify_migrations.py --environment=qa` | 69.859 | 0 |
| Environment prod | `tooling/verify_migrations.py --environment=prod` | 74.344 | 0 |
| Backup/restore | `tooling/verify_migrations.py --environment=dev --backup-restore` | 57.437 | 0 |
| Seeds dev | `tooling/verify_migrations.py --environment=dev --synthetic-seeds` | 87.172 | 0 |
| Seeds qa | `tooling/verify_migrations.py --environment=qa --synthetic-seeds` | 90.312 | 0 |
| Seeds prod | `tooling/verify_migrations.py --environment=prod --synthetic-seeds` | 46.515 | 0 |

The full suite covers delivered-version upgrades, preserved rows/checksums/history,
34 base changesets, storage constraints/index plans, authenticated runtime grants,
concurrent identity/idempotency/inbox/outbox/deactivation operations, full rollback
and rebuild, and preservation of foreign-owner fixtures and the external extension.
Environment tests cover migrator ownership, denied foreign/DDL access and bootstrap.
Recovery compares schema, ACLs, history and table data, checks restored runtime and
no-op migration, and rejects a corrupted archive without modifying its target.
Seed tests verify 35 changesets in dev/qa versus 34 in prod, explicit-context gates,
repeat updates, protected rollback, document collision and reapplication.
Expected negative SQL cases passed their assertions; no unexpected failures occurred.
Post-run inventory found no remaining `patients-*` containers or `patients-ci-*`
networks/volumes; unrelated running containers were not modified.

## Retained evidence

Archive filename: `patient-db-validation-20261103-4297e928.zip`, stored in the
parent `patients` workspace directory, outside the Git repository and PR diff.
It contains `manifest.json`, `docker-version.json`, `source.diff`, the initial
untracked-document snapshot and the nine complete stdout/stderr logs below.
Archive SHA-256: `675418fb6e343f12c822e85ac93a2fe71b8d9ec6f5e3f0d7d0740f893361f3d5`.
The archive is local evidence; attach it to the reviewed PR or an approved artifact
store and record that durable URL. No remote upload was performed.

| Log | SHA-256 |
|---|---|
| rollback-unit.log | `bb2df354da5a5f06847e24802e3a39c8bfe56d011d30a9c0df6d65edbaa96111` |
| full.log | `9e1a9bc11ddf0fc371565d77ba887ba4523ad2ec36dfacb83d6d6e3aa27a569f` |
| environment-dev.log | `51a8ba8df2ecc7f09094fdae27afae25aa607e69a1adcbe0700e23b8d8da290c` |
| environment-qa.log | `482e1dd9fb7aacf762bac5d2053f15a163f0cea28e78a8ec02cb5f899b8dde57` |
| environment-prod.log | `bc1efd98a6a2c496ca456b921a6119a4f300501bb090485a636f2fc5a6cf6667` |
| backup-restore.log | `79912295e329a179d5af6130b2fbd0236335f96497c529222a35813793745977` |
| seeds-dev.log | `a78d77c4502eb373c8919ca778786549b9f1c8d2593e9c808e15021e80c7ac06` |
| seeds-qa.log | `1cff9f3f3a227c7e270100c7105acf1ca08b4fcc30bf20fc8fc313a4e9ebc2a5` |
| seeds-prod.log | `4f7052df1a7fa32e4be09ff9e8062143c9b9590a34e6d7e4ac0d11aefe29fcfa` |

## Limits and acceptance handoff

The suite reproduces every configured workflow test command locally; remote Actions
was not run and remains budget-blocked. Project CI governance, canonical Docs
reconciliation, independent acceptance and actual deployment remain as recorded in
the acceptance matrix. Successful chronology checks certify this run, not permanent
host-clock stability. No API/provider integration or whole-HU completion is claimed.
