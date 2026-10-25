# dlc-patient-db

Patients database migrations for **Di Lucca Dental Care & Technology**.
The source of truth is [dlc-docs](https://github.com/code-corhuila/dlc-docs):
ADR-007 (Liquibase), ADR-008 (domain-owned migrations), `06-data/` and
`09-microservices/services/03-patients-service/`.

## Current scope

Bootstrap only: creates the empty `patients` schema and verifies reconstruction.
This does not implement or complete HU-PAT-001. Patient tables, constraints,
audit, concurrency, idempotency, inbox/outbox, seeds and runtime grants are pending.
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
Owner-scoped grants and integration with infrastructure remain to be verified.

```sh
docker compose --env-file .env -f deploy/compose.yml run --rm patients-db-migrate validate
docker compose --env-file .env -f deploy/compose.yml run --rm patients-db-migrate update
```

## Verify

Requires Python 3.12+ (standard library only) and a running Linux Docker engine.

```sh
python -B tooling/verify_migrations.py
```

The test creates disposable PostgreSQL with synthetic credentials, validates Compose
and Liquibase, applies migrations twice, checks unchanged history, reverses all
recorded changes and reapplies them. A foreign-owner fixture must survive.
Only its uniquely named test container and network are removed.
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
