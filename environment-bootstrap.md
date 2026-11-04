# Patients environment bootstrap

Based on dlc-docs ADR-008, `06-data/migration-strategy.md` and the Patients runbook.
Infrastructure provides one shared PostgreSQL per environment; Patients migrates only
its schema. Each environment has separate hosts, credentials and deployment approval.

## Provision and run

1. The authorized platform DBA runs `deploy/bootstrap.sql` in the selected database.
   It creates LOGIN roles `patients_migrator`, `patients_runtime` and `patients_app` (plus the NOLOGIN `patients_reader` and `patients_writer`) without elevated
   role attributes or memberships. Assign distinct passwords through the environment's
   secret manager. The SQL contains no passwords and installs no extensions.
2. Copy the example of the target environment, `deploy/env/dev.env.example`,
   `deploy/env/qa.env.example` or `deploy/env/main.env.example`, to the ignored file without
   `.example`, and set PG_MIGRATOR_PASSWORD_FILE to the absolute path of that environment's
   migrator secret. Each file fixes its own PG_ENVIRONMENT (`prod` remains an alias of `main`),
   runner project and engine host: Annex J.5.1 runs every environment as its own Compose
   project (`dlc-dev`, `dlc-qa`, `dlc-main`) with its own container and volume, so
   `dlc-<env>-dlc-postgres-1` is unique on the `platform` network. The runtime secret stays with the API.
   In qa and main back up and verify the restore before migrating, and never remove the volume (J.5.4).
3. Before other deployment steps, create the owner schema using the existing first changeset:
   `docker compose --env-file deploy/env/dev.env -f deploy/compose.environment.yml run --rm patients-db-migrate update-count --count=1`
4. The DBA re-runs the bootstrap immediately: schema ownership now suffices and database
   CREATE is revoked from the migrator. Verify the seal before continuing or starting the API.
5. Before updating to query indexes, infrastructure provisions pg_trgm and grants its
   operator-class namespace USAGE to patients_migrator; see [query prerequisites](query-indexes.md).
   Apply and validate the remaining migrations with the same runner:
   `docker compose --env-file deploy/env/dev.env -f deploy/compose.environment.yml run --rm patients-db-migrate validate`
   `docker compose --env-file deploy/env/dev.env -f deploy/compose.environment.yml run --rm patients-db-migrate update`
   Use `deploy/env/qa.env` or `deploy/env/main.env` for the other environments; contexts do not replace environment isolation.

The two canonical control tables stay in public: databasechangelog_patients and
databasechangeloglock_patients. Bootstrap prepares only these technical tables,
owned by patients_migrator; it grants no public CREATE. Repeating it preserves history,
object identities and active locks. Business schema/tables remain canonical changesets.
Existing schemas or technical tables with another owner require a separately reviewed
ownership transition; bootstrap refuses automatic adoption, copying or history resets.
Back up and verify restore before any transition of an existing installation.

## Verification and boundaries

`python -B tooling/verify_migrations.py --environment=dev` (also qa/main/prod) uses a unique
disposable PostgreSQL, three independent synthetic secrets and the actual secret-based
runner. It checks repeatable bootstrap, unsafe roles/foreign ownership, invalid/missing
environments, empty secrets, restricted ownership, upgrade through the delivered 26/27-change baselines to the current schema,
unchanged prior history/control-table OIDs, denied cross-owner/DDL/extension operations,
repeat update and the existing authenticated runtime suite. CI runs the three contexts.
The ordinary full migration/rollback job remains separate and uses the administrative
fixture; environment checks do not claim non-superuser full rollback verification.

The older deploy/compose.yml remains the disposable verifier's direct-credential runner.
Use compose.environment.yml for owner-scoped deployment. [Synthetic seeds](synthetic-seeds.md)
require explicit dev/qa contexts and exclude prod. Their verifier runs separately.
The [disposable backup/restore drill](backup-restore.md) is local recovery evidence.
No real dev/qa/prod deployment, secret-manager integration, live ownership conversion
or real-infrastructure restore is claimed. Deployment operator and infrastructure bindings
must be recorded with the reviewed revision before acceptance.
