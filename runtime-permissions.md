# Patients runtime permissions

Source: dlc-docs ADR-008, `06-data/migration-strategy.md` and
`09-microservices/services/03-patients-service/data-model.md`.
Runtime persistence access is separate from business authorization in use cases.

`patients_runtime` is the technical role selected by this DB increment. Infrastructure
must provision it and its credential/database connection separately before migration.
No CREATE/ALTER ROLE, passwords, database-wide changes or foreign-owner grants belong
to this changeset. The disposable test role is synthetic provisioning, not deployment evidence.

The precondition requires an existing role without superuser, CREATEDB, CREATEROLE,
replication, BYPASSRLS or memberships, without database/public CREATE, and without
pre-existing schema/table/column access to Patients. A clean baseline makes grant
rollback unambiguous. Do not use a migration owner as runtime or bypass a failed precondition.
External provisioning must also prevent access to other owners, Liquibase metadata,
role escalation and unexpected inherited/PUBLIC privileges; verify effective access
with the actual deployment credential. This migration cannot revoke privileges supplied
by another role, PUBLIC or later infrastructure changes.

| Object | Runtime grants |
|---|---|
| patients schema | USAGE only |
| patients | SELECT, INSERT; UPDATE document/name/birth/contact/address/status/version and update actor/time columns |
| emergency_contacts | SELECT, INSERT, DELETE; UPDATE name, relationship and phone only |
| patient_audit | SELECT, INSERT only |
| idempotency_records | SELECT, INSERT, DELETE; the existing retention trigger rejects premature deletion |
| outbox_events / inbox_events | SELECT, INSERT; UPDATE status, attempts, next_retry_at and error_code only |

Worker markers are stamped by invoker triggers; UPDATE grants on publication/processing
instants are unnecessary. Existing immutable-fact and audit triggers remain active.
Profiles cannot be hard-deleted. Identity/creation fields, event facts and retry results
cannot be rewritten through UPDATE. No grant option, persistent DDL, TRUNCATE, trigger
management, future-object defaults or Liquibase access is granted.

The grant-only rollback revokes exactly this increment's table/column/schema permissions;
it does not delete data, drop the externally managed role or change its credentials.
Shared-environment recovery still requires reviewed forward corrections.

Tests authenticate as the runtime login over TCP, exercise all six tables and worker
row locks, and reject foreign-owner/metadata access, persistent DDL, role escalation,
trigger disabling, history rewrites and unexpected access to a future table. Temporary
helpers use the disposable database's TEMP privilege; database/PUBLIC policy, deployment
secrets and a non-superuser migration-identity integration remain external work.
