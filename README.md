# dlc-patient-db

Patients database migrations for **Di Lucca Dental Care & Technology**.
The source of truth is [dlc-docs](https://github.com/code-corhuila/dlc-docs):
ADR-007 (Liquibase), ADR-008 (domain-owned migrations), `06-data/` and
`09-microservices/services/03-patients-service/`.

## Current scope

Includes the bootstrap and administrative `patients.patients` identity table,
contract field limits, immutable identifier and normalized document uniqueness
across active/inactive profiles. Emergency contacts support zero or more entries,
contract field limits and an indexed local patient reference with restricted deletion.
Append-only administrative audit records include actor, action, profile version,
server time, field names and a required deactivation reason. See [data dictionary](data-dictionary.md).
This is an increment of HU-PAT-001, not complete functional acceptance.
Completed retry outcomes are stored by principal, operation, resource and UUID key,
with an immutable request hash/response and at least seven days of retention.
The local outbox stores patient lifecycle events and their publication metadata,
with immutable facts and indexed pending batches.
The inbox stores assignment events with event/source deduplication and local processing markers.
Atomic profile/audit/outbox writes, optimistic update orchestration, guarded
deactivation, HTTP replay handling, inbox consumer, broker relay and seeds remain pending.
Explicit least-privilege runtime grants are included; see [runtime permissions](runtime-permissions.md).
No clinical history, credentials, appointment or financial data belongs here.

## Layout

- `01_ddl/`: schema definitions; foreign keys will follow table creation.
- `02_dml/`, `03_dcl/`, `04_tcl/`: seeds, permissions and transaction operations.
- `05_rollbacks/`: explicit SQL reversals, without cross-owner cascading drops.
- `changelog/changelog-master.yaml`: the single Liquibase entry point.
- `deploy/compose.yml`: migration runner only; no database service or owned volume.
- `tooling/verify_migrations.py`: executable reconstruction test used by CI.

## Run migrations

Requires Docker Compose and an existing PostgreSQL instance/network provisioned
by `dlc-infra-postgres`. Copy `.env.example` to `.env` and supply local values.
The migration credential must be provisioned separately from the runtime user.
This bootstrap needs schema creation and access to its own Liquibase control tables
in `public`: `databasechangelog_patients` and `databasechangeloglock_patients`.
Those are technical metadata; business tables belong only to `patients`.
Provision `patients_runtime` separately before update; migrations do not create roles or credentials.
Owner-scoped migration credentials and integration with infrastructure remain to be verified.

```sh
docker compose --env-file .env -f deploy/compose.yml run --rm patients-db-migrate validate
docker compose --env-file .env -f deploy/compose.yml run --rm patients-db-migrate update
```

## Verify

Requires Python 3.12+ (standard library only) and a running Linux Docker engine.

```sh
python -B tooling/verify_migrations.py
```

For a focused empty-store/storage check, add `--schema-smoke`; this does not run
historical upgrade or rollback verification. CI keeps the full default command.

The test creates disposable PostgreSQL with synthetic credentials, validates Compose
and Liquibase, applies migrations twice, checks unchanged history, reverses all
recorded changes and reapplies them. It also upgrades from the delivered bootstrap,
checks patient constraints and races two normalized identities using separate
connections while the first insert is uncommitted. Contact checks cover orphan rejection,
required fields, limits, cardinality and retention after deactivation. Upgrade and
increment-only rollback must preserve an existing patient and prior migration history.
Audit checks reject destructive writes, unsafe field metadata and missing deactivation
reasons; audit-only rollback also preserves existing contacts and prior history.
Local transaction checks verify that failed audit inserts or later failures roll
back both profile and audit changes; API/outbox orchestration remains pending.
Retry checks cover scope separation, concurrent keys, immutable results, retention
and journal/profile rollback. Migration files are copied unchanged to a disposable
Linux volume for verification; the production Compose runner retains its read-only bind mount.
Outbox checks cover event identity, payload keys, publication transitions, local
transaction rollback and disjoint row-lock claims; no broker delivery is claimed.
Inbox checks cover both deduplication keys, concurrent delivery, immutable facts,
retry/processing states and atomic local effect markers. A foreign-owner fixture must survive.
Runtime checks authenticate a separate synthetic login and verify allowed DML, denied
persistent DDL, metadata/foreign-owner access and grant rollback. Missing/unsafe roles
block migration; future tables receive no automatic runtime grants.
Only its uniquely named test container, network and migration snapshot volume are removed.
Rollback checks reject non-monotonic migration timestamps before reversal;
inspect host/database clock synchronization if this guard fails.
Full rollback is for disposable tests; shared-environment recovery uses reviewed
forward corrections. Never edit an applied changeset.

## Contribution

Use child branches and PRs; never commit directly to `develop`, `qa` or `main`.
Keep each PR within 400 added/deleted lines, including tests and documentation.
Follow RED -> GREEN -> REFACTOR and attach revision-specific evidence.
Promotion uses `git cherry-pick -x`; permanent branches are never merged together.
Follow `00-governance/branching-policy.md` and `git-conventions.md` in `dlc-docs`;
their promotion-prefix discrepancy must be resolved before promotion.
Preserve CODEOWNERS; `main` requires approval from `ariel5253`.
Green CI alone does not establish acceptance under `quality-gates.md`.
