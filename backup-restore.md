# Patients backup and restore verification

Sources of truth: dlc-docs `06-data/migration-strategy.md`, `06-data/models.md`
and `09-microservices/services/03-patients-service/runbook.md` sections 4-6.
This drill verifies a complete synthetic database, not a schema-only export.
It does not alter business migrations or deploy any shared environment.

Run with Python 3.12+ and Linux Docker:

```sh
python -B tooling/verify_migrations.py --environment=dev --backup-restore
```

The recovery mode provisions a uniquely named disposable PostgreSQL 16.6, external
pg_trgm fixture and owner roles, seals database CREATE and applies all 34 changesets.
The existing environment-verification jobs retain their separate upgrade checks.
Committed synthetic data covers all seven Patients tables, including request replay,
pending inbox/outbox facts and an unresolved deactivation guard. A foreign-owner
marker and owner-specific Liquibase history/lock tables are included in the copy.

The drill uses pg_dump custom format for the whole source database, checks the
archive listing and SHA-256, then restores to a fresh template0 database using
pg_restore --exit-on-error --single-transaction. No --clean or source deletion is used.
A truncated archive must fail without changing a separate empty rejection target.
The archive and its deliberately damaged copy remain inside the test container;
the verifier's existing finally block removes that container and its disposable storage.
No database dump, credentials or patient contents are written into this repository.

Compare schema-only dump SHA-256 (owners, object/column ACLs, default privileges,
constraints, indexes, functions and triggers) against an independent plain source
schema export loaded into a separate reference database. This gives both definitions
one parser round trip: PostgreSQL flattens nested CHECK conjunctions on reload.
No constraints or ACLs are stripped from comparison. Compare counts/sorted row
digests with the original source for every non-system table.
This small, quiescent fixture permits whole-table digest
aggregation; it is not a production-scale reconciliation implementation.
Liquibase validate/update must succeed against the restored database without
changing its history. Authenticate independently as patients_runtime and check
owned reads/writes, duplicate rejection, foreign keys and denied DDL/metadata/foreign
access. Verification rolls back its writes. Pending guarded outcomes remain pending.
Finally require the original source and restored fingerprints to remain unchanged.

Roles are cluster-global prerequisites and already exist in this same disposable
cluster; pg_dump does not back them up. Database-level CONNECT is explicitly
provisioned for the fresh target; it is not claimed to come from the archive.
The drill does not verify cluster recreation, role/password recovery, other services'
real schemas, broker reconciliation, Clinical MongoDB, WAL/PITR or off-site backups.
Its elapsed time is local drill evidence, not a measured service RPO/RTO commitment.

Before real recovery, the authorized infrastructure operator must select a trusted,
protected backup, verify PostgreSQL/extension compatibility, roles and database
privileges, coordinate all shared-store owners and isolate a fresh recovery target.
Record backup timestamp/checksum, application and migration revisions, operator,
environment and reconciliation findings. Reconcile pending operations/events with
their owners before resuming workers; restoration never proves a guard was aborted.
Do not reset migration history, replay destructive rollbacks or overwrite the live
shared database using this test procedure. Production corrections remain forward-only.
Real deployment/restore evidence and owner acceptance remain pending.

References: PostgreSQL 16 [pg_dump](https://www.postgresql.org/docs/16/app-pgdump.html)
and [pg_restore](https://www.postgresql.org/docs/16/app-pgrestore.html).
