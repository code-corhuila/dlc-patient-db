# Synthetic Patients seeds

Sources: dlc-docs `06-data/migration-strategy.md` execution rules,
`10-devops/environments.md` and the Patients owner data model/runbook.
Applied DDL remains unchanged. The new owner-local changeset is
`patients-dml-synthetic-001`, author DanielPerez1822, under `02_dml/00_inserts`.
It follows the canonical DML include after DDL; verify shared sequencing before deployment.

| Snapshot | Stable identifier | State / contacts |
|---|---|---|
| Synthetic Active | f2000000-0000-4000-8000-000000000001 | ACTIVE; two synthetic contacts |
| Synthetic Inactive | f2000000-0000-4000-8000-000000000002 | INACTIVE; no contacts |

Documents are SYNTHETIC-PAT-001/002, email is synthetic@example.invalid and phone
is 0000000000. The f2200000-0000-4000-8000-000000000001 actor is a synthetic
reference, not an Auth identity or usable login. Contact IDs use f2100000 with
suffixes 001/002. All values are fake; no other owner's schema is written.
These are initial storage snapshots, not evidence of registration/deactivation
use cases. No audit, idempotency, guard, inbox or outbox facts are fabricated;
no notifications or clinical/appointment assignments are initiated.

The normal environment runner passes PG_ENVIRONMENT as the Liquibase context.
The seed requires explicit dev or qa and excludes prod, including mixed dev,prod.
The @ context marker also excludes runs with no context. Run migrations using
the existing environment bootstrap procedure; no second seed entry point is used.
Mislabeling a real environment as dev/qa is an operator/configuration error that
contexts cannot detect. This is not deployment or acceptance evidence.

Liquibase records the seed once; repeated update preserves data and history.
Plain inserts reject UUID/document collisions without overwriting existing rows.
The transactional rollback removes only exact unchanged snapshots. Modified rows
or new dependent references abort the whole reversal and preserve history/data.
Never bypass guards, cascade-delete, disable triggers or purge immutable journals
to undo evolved fixtures. Review forward correction instead.

CI runs `python -B tooling/verify_migrations.py --environment=dev --synthetic-seeds`
and its qa/prod variants against separate disposable databases. It checks explicit
context isolation, runtime reads, repeats, collisions, protected rollback, reapply
and preservation of unrelated records and prior migration history. Existing
schema/upgrade/recovery suites exclude the synthetic-seeds label to keep their
independent fixtures isolated; the environment runner itself does not exclude it.

Reference: [Liquibase contexts and explicit @ selection](https://docs.liquibase.com/reference-guide/changelog-attributes/what-are-contexts).
