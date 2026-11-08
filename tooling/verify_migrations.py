"""Rebuild only Patients in a disposable PostgreSQL database; requires Docker."""

import difflib
import hashlib
import json
import re
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import time
import unittest
import uuid

from rollback_verification import RollbackPreflightError, run_rollback


ROOT = Path(__file__).resolve().parents[1]
# The engine pinned by dlc-infra-postgres; override only with another pinned postgres tag.
INFRASTRUCTURE_POSTGRES_IMAGE = "postgres:17.11-alpine3.24"


def postgres_image(environ):
    image = environ.get("PATIENTS_POSTGRES_IMAGE", INFRASTRUCTURE_POSTGRES_IMAGE)
    if not re.fullmatch(r"postgres:\d+\.\d+-alpine(\d+\.\d+)?", image):
        raise ValueError("PATIENTS_POSTGRES_IMAGE must be a pinned postgres:<major>.<minor>-alpine tag")
    return image


def schema_digest(dump):
    # pg_dump 17.6+ and 16.10+ wrap every dump in a random \restrict key; it is not schema.
    lines = (line for line in dump.splitlines() if not re.match(r"\\(un)?restrict ", line))
    return hashlib.sha256("\n".join(lines).encode()).hexdigest()
SCHEMA_SMOKE = False
ENVIRONMENT = None
BACKUP_RESTORE = False
SYNTHETIC_SEEDS = False
# Annex J.5 names the production environment main; prod stays accepted as its alias.
PRODUCTION = ("main", "prod")


class MigrationRebuildTest(unittest.TestCase):
    def test_update_repeat_rollback_and_reapply_preserve_other_owners(self):
        self.assertIn(ENVIRONMENT, (None, "dev", "qa", "main", "prod"))
        compose = ROOT / "deploy" / ("compose.environment.yml" if ENVIRONMENT else "compose.yml")
        POSTGRES_IMAGE = postgres_image(os.environ)
        print("Disposable PostgreSQL image: " + POSTGRES_IMAGE, flush=True)
        self.assertTrue(compose.is_file(), "Patients migration runner is missing")
        suffix = uuid.uuid4().hex[:12]
        network = f"patients-ci-{suffix}"
        snapshot = f"{network}-migrations"
        container = f"patients-postgres-{suffix}"
        env = dict(os.environ, PG_HOST=container, PG_PORT="5432",
                   PG_DATABASE="patients_ci", PG_MIGRATION_USER="postgres",
                   PG_MIGRATION_PASSWORD=secrets.token_hex(24),
                   PG_RUNTIME_TEST_PASSWORD=secrets.token_hex(24), PG_APP_TEST_PASSWORD=secrets.token_hex(24),
                   PG_OWNER_TEST_PASSWORD=secrets.token_hex(24), PG_NETWORK=network)

        if ENVIRONMENT:
            temporary = tempfile.TemporaryDirectory(prefix="patients-env-")
            self.assertEqual(Path(temporary.name).resolve().parent, Path(tempfile.gettempdir()).resolve())
            self.addCleanup(temporary.cleanup)
            password_file = Path(temporary.name) / "migrator-password"
            password_file.write_text(env["PG_OWNER_TEST_PASSWORD"])
            env.update(PG_ENVIRONMENT=ENVIRONMENT, PG_MIGRATOR_PASSWORD_FILE=str(password_file))

        def redact(output):
            for key in ("PG_MIGRATION_PASSWORD", "PG_RUNTIME_TEST_PASSWORD", "PG_APP_TEST_PASSWORD", "PG_OWNER_TEST_PASSWORD"):
                output = output.replace(env[key], "[REDACTED]")
            return output

        def run(*args, check=True, input_text=None, return_result=False):
            try:
                result = subprocess.run(args, cwd=ROOT, env=env, text=True,
                                        capture_output=True, timeout=180, input=input_text)
            except subprocess.TimeoutExpired:
                self.fail("Docker command exceeded 180 seconds; check engine/registry access")
            if check and result.returncode:
                # Credentials must not appear in failure diagnostics.
                output = redact(result.stdout + result.stderr)
                self.fail(output)
            return result if return_result else result.stdout.strip()

        psql = ["docker", "exec", container, "psql", "-U", "postgres",
                "-d", env["PG_DATABASE"], "-v", "ON_ERROR_STOP=1", "-Atc"]

        def sql(statement):
            return run(*psql, statement)

        support = (ROOT / "tooling/tests/support.sql").read_text()

        def sql_script(script, check=True):
            return run("docker", "exec", "-i", container, "psql", "-U", "postgres",
                "-d", env["PG_DATABASE"], "-v", "ON_ERROR_STOP=1",
                input_text=script, check=check, return_result=not check)

        inbox_support = (ROOT / "tooling/tests/inbox_support.sql").read_text()
        legacy_tables = {"patient": "patients", "emergency_contact": "emergency_contacts",
                         "idempotency_record": "idempotency_records", "outbox_event": "outbox_events",
                         "inbox_event": "inbox_events", "deactivation_operation": "deactivation_operations"}
        # Upgrade stages run before the naming migration, so they still see the delivered plural names.

        def to_legacy(script):
            script = re.sub(r"\bpatients\.(" + "|".join(legacy_tables) + r")\b",
                            lambda m: "patients." + legacy_tables[m[1]], script)
            for singular, plural in legacy_tables.items():
                keep = "(?!_audit)" if singular == "patient" else ""
                script = re.sub(r"\b(chk|fk|pk|uk|idx|trg)_" + singular + keep + r"(?=_|\b)",
                                lambda m, p=plural: ("ck" if m[1] == "chk" else m[1]) + "_" + p, script)
            return script.replace("idx_inbox_events_pending", "ix_inbox_events_pending")

        legacy_support = to_legacy(support)

        def storage_checks():
            for name in ("patient_identity", "emergency_contacts", "patient_audit", "idempotency_records", "outbox_events", "inbox_events", "deactivation_operations", "patient_query_indexes", "naming_conventions", "deactivation_invariant"):
                print("Storage checks: " + name, flush=True)
                fixture = inbox_support if name == "inbox_events" else ""
                result = sql_script("BEGIN;\n" + support + fixture + (ROOT / f"tooling/tests/{name}.sql").read_text())
                if name == "patient_query_indexes":
                    print(result, flush=True)

        def role_sql(user, password, script, check=True):
            return run("docker", "exec", "-i", "-e", "PGPASSWORD=" + password, container,
                "psql", "-h", "127.0.0.1", "-U", user, "-d", env["PG_DATABASE"],
                "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose", input_text=script,
                check=check, return_result=not check)

        def runtime_sql(script, check=True):
            return role_sql("patients_runtime", env["PG_RUNTIME_TEST_PASSWORD"], script, check)

        def runtime_denied():
            result = runtime_sql("SELECT count(*) FROM patients.patient;", check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("42501", result.stderr)

        def runtime_checks(legacy=False):
            print("Runtime checks: authenticated least-privileged connection", flush=True)
            sql("CREATE TABLE patients.runtime_future_probe (id integer)")
            try:
                script = ("BEGIN;\n" + support + inbox_support +
                          (ROOT / "tooling/tests/runtime_permissions.sql").read_text())
                runtime_sql(to_legacy(script) if legacy else script)
                if not legacy:
                    role_sql("patients_app", env["PG_APP_TEST_PASSWORD"], "BEGIN;" + chr(10) + support +
                             (ROOT / "tooling/tests/domain_roles.sql").read_text())
            finally:
                sql("DROP TABLE patients.runtime_future_probe RESTRICT")

        def concurrent_identity_check():
            def insert(n, kind, number):
                return ("INSERT INTO patients.patient (patient_id, document_type, "
                        "document_number, name, birth_date, phone, email, created_by, updated_by) "
                        f"VALUES ('00000000-0000-4000-8000-{n:012d}', '{kind}', '{number}', "
                        "'Synthetic Race', '2000-01-01', '3000000000', 'race@example.invalid', "
                        "'10000000-0000-4000-8000-000000000001', "
                        "'10000000-0000-4000-8000-000000000001'); ")

            concurrent_insert_check(insert(10, 'CC', 'RACE-01'), insert(11, ' cc ', ' race-01 '),
                                    'uk_patient_document')
            self.assertEqual(sql("SELECT count(*) FROM patients.patient"), "1")

        def concurrent_insert_check(first_insert, second_insert, constraint):
            first = subprocess.Popen([*psql, "SET application_name = 'patients-race'; "
                "BEGIN; " + first_insert + "SELECT pg_sleep(8); COMMIT;"],
                cwd=ROOT, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                wait_for_transaction(first)
                second = run(*psql, second_insert,
                             check=False, return_result=True)
                self.assertNotEqual(second.returncode, 0)
                self.assertTrue(any(name in second.stderr for name in
                    (constraint if isinstance(constraint, tuple) else (constraint,))), second.stderr)
            finally:
                _, error = first.communicate(timeout=30)
            self.assertEqual(first.returncode, 0, error)

        def wait_for_transaction(first):
            for _ in range(40):
                if sql("SELECT count(*) FROM pg_stat_activity WHERE "
                       "application_name = 'patients-race' AND wait_event = 'PgSleep'") == "1":
                    return
                self.assertIsNone(first.poll(), "First transaction ended before the race")
                time.sleep(0.1)
            self.fail("First transaction did not reach its held write or row lock")

        def concurrent_outbox_claim_check():
            sql("INSERT INTO patients.outbox_event (event_id,aggregate_id,event_type,occurred_at,payload,correlation_id,causation_id) "
                "SELECT ('50000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid, "
                "'00000000-0000-4000-8000-000000000010','PatientProfileUpdated',statement_timestamp(), "
                "jsonb_build_object('patientId','00000000-0000-4000-8000-000000000010','changedFields',jsonb_build_array('phone'), "
                "'updatedAt',statement_timestamp(),'updatedBy','10000000-0000-4000-8000-000000000001'), "
                "'60000000-0000-4000-8000-000000000001','70000000-0000-4000-8000-000000000001' FROM (VALUES (10),(11)) s(n)")
            claim = ("SELECT event_id FROM patients.outbox_event WHERE status='PENDING' AND next_retry_at<=clock_timestamp() "
                     "ORDER BY next_retry_at,recorded_at,event_id LIMIT 1 FOR UPDATE SKIP LOCKED")
            first = subprocess.Popen([*psql,"SET application_name='patients-race'; BEGIN; " + claim + "; SELECT pg_sleep(8); COMMIT;"],
                cwd=ROOT,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            try:
                wait_for_transaction(first)
                self.assertEqual(sql(claim),'50000000-0000-4000-8000-000000000011')
            finally:
                output,error = first.communicate(timeout=30)
            self.assertEqual(first.returncode,0,error)
            self.assertIn('50000000-0000-4000-8000-000000000010',output)

        def concurrent_idempotency_check():
            statement = ("INSERT INTO patients.idempotency_record (actor_kind, actor_subject, operation, "
                "target_resource, idempotency_key, request_hash, response_status, response_body) VALUES "
                "('SERVICE','patients-ci','register','/patients','40000000-0000-4000-8000-000000000010',"
                "repeat('a',64),201,'{}'); ")
            concurrent_insert_check(statement, statement, 'pk_idempotency_record')
            self.assertEqual(sql("SELECT count(*) FROM patients.idempotency_record"), "1")

        def concurrent_inbox_check():
            def receive(event_id, version):
                return inbox_support + f"SELECT pg_temp.receive_assignment('{event_id}',{version});"

            first_id = '80000000-0000-4000-8000-000000000001'
            concurrent_insert_check(receive(first_id, 1), receive(first_id, 1),
                                    ('pk_inbox_event', 'uk_inbox_event_source'))
            # Different event IDs for one source fact must race on source uniqueness.
            concurrent_insert_check(receive('80000000-0000-4000-8000-000000000002', 2),
                                    receive('80000000-0000-4000-8000-000000000003', 2), 'uk_inbox_event_source')
            self.assertEqual(sql("SELECT count(*) FROM patients.inbox_event"), "2")

        def concurrent_deactivation_check():
            statement = ("INSERT INTO patients.deactivation_operation "
                "(operation_id,patient_id,actor_id,idempotency_key,expected_version,reason_code,reason) VALUES "
                "('b1000000-0000-4000-8000-000000000010','00000000-0000-4000-8000-000000000010',"
                "'10000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000010',1,'OTHER','Synthetic intent');")
            concurrent_insert_check(statement, statement.replace('b1000000-0000-4000-8000-000000000010',
                'b1000000-0000-4000-8000-000000000011'), 'uk_deactivation_operation_request')
            self.assertEqual(sql("SELECT count(*) FROM patients.deactivation_operation"), "1")

        def migrate(*args, check=True, include_seeds=False, direct=False):
            if not include_seeds and args[0] in ("update", "update-count"):
                filtered = any(arg.startswith("--label-filter=") for arg in args)
                args = tuple(arg + " and !synthetic-seeds" if arg.startswith("--label-filter=") else arg for arg in args)
                if not filtered:
                    args += ("--label-filter=!synthetic-seeds",)
            print("Liquibase: " + " ".join(args), flush=True)
            runner = ROOT / "deploy/compose.yml" if direct else compose
            def execute():
                return run("docker", "compose", "-p", network, "-f", str(runner),
                           "run", "--rm", "-v", f"{snapshot}:/workspace:ro", "patients-db-migrate", *args,
                           check=check, return_result=not check)
            if args[0] == "rollback-count":
                recorded = json.loads(sql("SELECT coalesce(json_agg(h ORDER BY orderexecuted),'[]'::json) FROM "
                    "(SELECT id,author,filename,orderexecuted,dateexecuted FROM public.databasechangelog_patients) h"))
                print("Rollback preflight history: " + json.dumps(recorded), flush=True)
                try:
                    count = int(next(arg.split("=", 1)[1] for arg in args if arg.startswith("--count=")))
                except (ValueError, StopIteration):
                    self.fail("Rollback requires an explicit integer --count")
                try:
                    return run_rollback(recorded, count, execute)
                except RollbackPreflightError as error:
                    self.fail("Rollback blocked before invoking Liquibase: " + str(error))
            return execute()

        def environment_checks():
            bootstrap_sql = (ROOT / "deploy/bootstrap.sql").read_text()
            sql_script(bootstrap_sql)
            sql_script(bootstrap_sql)
            sql("GRANT USAGE ON SCHEMA query_extensions TO patients_migrator")
            metadata = "SELECT oid,relowner FROM pg_class WHERE oid IN ('public.databasechangelog_patients'::regclass,'public.databasechangeloglock_patients'::regclass) ORDER BY oid"
            before_metadata = sql(metadata)
            sql("ALTER ROLE patients_runtime CREATEROLE")
            try:
                self.assertNotEqual(sql_script(bootstrap_sql, check=False).returncode, 0)
            finally:
                sql("ALTER ROLE patients_runtime NOCREATEROLE")
            sql("ALTER ROLE patients_migrator PASSWORD '" + env["PG_OWNER_TEST_PASSWORD"] + "'; "
                "ALTER ROLE patients_runtime PASSWORD '" + env["PG_RUNTIME_TEST_PASSWORD"] + "'; "
                "ALTER ROLE patients_app PASSWORD '" + env["PG_APP_TEST_PASSWORD"] + "'")
            if BACKUP_RESTORE or SYNTHETIC_SEEDS:
                migrate("update-count", "--count=1")
                sql_script(bootstrap_sql)
                migrate("update")
                self.assertEqual(sql("SELECT count(*) FROM public.databasechangelog_patients"), "39")
                return
            for bad_environment in ("staging", ""):
                env["PG_ENVIRONMENT"] = bad_environment
                try:
                    rejected = migrate("validate", check=False)
                    self.assertNotEqual(rejected.returncode, 0)
                    self.assertIn("PG_ENVIRONMENT", rejected.stdout + rejected.stderr)
                finally:
                    env["PG_ENVIRONMENT"] = ENVIRONMENT
            password_file.write_text("")
            try:
                rejected = migrate("validate", check=False)
                self.assertNotEqual(rejected.returncode, 0)
                self.assertIn("Empty migrator secret", rejected.stdout + rejected.stderr)
            finally:
                password_file.write_text(env["PG_OWNER_TEST_PASSWORD"])
            migrate("validate")
            migrate("update-count", "--count=1")
            sql_script(bootstrap_sql)
            self.assertEqual(sql("SELECT has_database_privilege('patients_migrator',current_database(),'CREATE')"), "f")
            migrate("update", "--label-filter=!runtime and !deactivation-operations and !query-indexes")
            history = "SELECT id,md5sum,dateexecuted FROM public.databasechangelog_patients"
            baseline = sql(history + " WHERE orderexecuted<=26 ORDER BY orderexecuted")
            sql("ALTER SCHEMA patients OWNER TO postgres")
            try:
                rejected = sql_script(bootstrap_sql, check=False)
                self.assertNotEqual(rejected.returncode, 0)
                self.assertIn("another owner", rejected.stderr)
            finally:
                sql("ALTER SCHEMA patients OWNER TO patients_migrator")
            sql_script(bootstrap_sql)  # Seal database CREATE after schema creation.
            self.assertEqual(sql("SELECT has_database_privilege('patients_migrator',current_database(),'CREATE')"), "f")
            migrate("update", "--label-filter=!deactivation-operations and !query-indexes")
            self.assertEqual(sql(history + " WHERE orderexecuted<=26 ORDER BY orderexecuted"), baseline)
            old_history = sql(history + " ORDER BY orderexecuted")
            migrate("update", "--label-filter=!query-indexes")
            self.assertEqual(sql(history + " WHERE orderexecuted<=27 ORDER BY orderexecuted"), old_history)
            query_baseline = sql(history + " ORDER BY orderexecuted")
            sql("REVOKE USAGE ON SCHEMA query_extensions FROM patients_migrator")
            try:
                rejected = migrate("update", check=False)
                self.assertNotEqual(rejected.returncode, 0)
                self.assertIn("pg_trgm", rejected.stdout + rejected.stderr)
                self.assertEqual(query_index_count(), "0")
            finally:
                sql("GRANT USAGE ON SCHEMA query_extensions TO patients_migrator")
            migrate("update")
            self.assertEqual(sql(history + " WHERE orderexecuted<=33 ORDER BY orderexecuted"), query_baseline)
            self.assertEqual(sql("SELECT count(*) FROM public.databasechangelog_patients"), "39")
            storage_checks()
            for query in (
                "SELECT pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname='patients'",
                "SELECT DISTINCT pg_get_userbyid(relowner) FROM pg_class WHERE relnamespace='patients'::regnamespace",
                "SELECT DISTINCT pg_get_userbyid(proowner) FROM pg_proc WHERE pronamespace='patients'::regnamespace"):
                self.assertEqual(sql(query), "patients_migrator")
            for statement in ("CREATE SCHEMA forbidden", "CREATE TABLE public.forbidden(id integer)",
                              "CREATE EXTENSION pgcrypto", "SELECT * FROM bootstrap_probe.marker",
                              "UPDATE bootstrap_probe.marker SET id=2", "DROP TABLE bootstrap_probe.marker",
                              "SET ROLE postgres", "CREATE ROLE forbidden"):
                denied = role_sql("patients_migrator", env["PG_OWNER_TEST_PASSWORD"], statement, check=False)
                self.assertNotEqual(denied.returncode, 0)
                self.assertIn("42501", denied.stderr)
            recorded = sql(history + " ORDER BY orderexecuted")
            migrate("update")
            self.assertEqual(sql(history + " ORDER BY orderexecuted"), recorded)
            self.assertEqual(sql(metadata), before_metadata)
            runtime_checks()
            self.assertEqual(sql("SELECT id FROM bootstrap_probe.marker"), "1")
            print("Environment PASS: " + ENVIRONMENT, flush=True)

        def query_index_count():
            return sql("SELECT count(*) FROM pg_indexes WHERE schemaname='patients' AND indexname IN "
                "('idx_patient_created_at_patient_id','idx_patient_status_created_at_patient_id','idx_patient_name_document_search')")

        def backup_restore_checks():
            source = env["PG_DATABASE"]
            recovered = "patients_recovered"
            definitions = {}

            def recovery_sql(database, statement):
                return run("docker", "exec", container, "psql", "-U", "postgres", "-d", database,
                    "-v", "ON_ERROR_STOP=1", "-Atc", statement)

            def fingerprint(database):
                tables = recovery_sql(database, "SELECT schemaname,tablename FROM pg_tables "
                    "WHERE schemaname NOT IN ('pg_catalog','information_schema') ORDER BY 1,2")
                rows = {}
                for table in tables.splitlines():
                    schema, name = table.split('|')
                    quoted = '.'.join('"' + part.replace('"', '""') + '"' for part in (schema, name))
                    rows[table] = recovery_sql(database, "SELECT count(*),md5(coalesce("
                        "string_agg(to_jsonb(t)::text,E'\\n' ORDER BY to_jsonb(t)::text),'')) FROM " + quoted + " t")
                definition = run("docker", "exec", container, "pg_dump", "-U", "postgres",
                    "-d", database, "--schema-only")
                definitions[database] = definition
                return schema_digest(definition), rows

            sql_script("BEGIN;\n" + support + inbox_support +
                (ROOT / "tooling/tests/backup_restore_fixture.sql").read_text())
            before = fingerprint(source)
            self.assertEqual(len(before[1]), 10, "Expected seven Patients tables, two history tables and foreign marker")
            self.assertTrue(all(int(value.split('|')[0]) > 0 for value in before[1].values()))
            started = time.monotonic()
            # Parse the independent plain schema export once, like the archive restore.
            # PostgreSQL flattens nested CHECK conjunctions during that round trip.
            reference = "patients_recovery_schema"
            run("docker", "exec", container, "createdb", "-U", "postgres", "-T", "template0", reference)
            run("docker", "exec", "-i", container, "psql", "-U", "postgres", "-d", reference,
                "-v", "ON_ERROR_STOP=1", input_text=definitions[source])
            expected = (fingerprint(reference)[0], before[1])
            archive = "/tmp/patients-recovery.dump"
            run("docker", "exec", container, "pg_dump", "-U", "postgres", "-d", source,
                "--format=custom", "--file=" + archive)
            archive_digest = run("docker", "exec", container, "sha256sum", archive)
            run("docker", "exec", container, "pg_restore", "--list", archive)
            # Files remain inside the disposable container; no binary shell pipeline on Windows.
            run("docker", "exec", container, "sh", "-ec",
                "head -c 128 /tmp/patients-recovery.dump > /tmp/patients-recovery-corrupt.dump")
            failed = "patients_recovery_rejected"
            run("docker", "exec", container, "createdb", "-U", "postgres", "-T", "template0", failed)
            empty = fingerprint(failed)
            rejected = run("docker", "exec", container, "pg_restore", "-U", "postgres", "-d", failed,
                "--exit-on-error", "--single-transaction", "/tmp/patients-recovery-corrupt.dump",
                check=False, return_result=True)
            self.assertNotEqual(rejected.returncode, 0, "Damaged archive was accepted")
            self.assertEqual(fingerprint(failed), empty, "Damaged restore changed the target")
            run("docker", "exec", container, "createdb", "-U", "postgres", "-T", "template0", recovered)
            run("docker", "exec", container, "pg_restore", "-U", "postgres", "-d", recovered,
                "--exit-on-error", "--single-transaction", archive)
            restored = fingerprint(recovered)
            if restored != expected:
                print('\n'.join(difflib.unified_diff(definitions[reference].splitlines(),
                    definitions[recovered].splitlines(), fromfile="reference schema", tofile="restored schema")), flush=True)
            self.assertEqual(restored, expected, "Restored schema, ACLs or table contents differ")
            recovery_sql(recovered, "GRANT CONNECT ON DATABASE patients_recovered TO patients_migrator,patients_runtime")
            try:
                env["PG_DATABASE"] = recovered
                migrate("validate")
                migrate("update")
                history = role_sql("patients_migrator", env["PG_OWNER_TEST_PASSWORD"],
                    "SELECT count(*) FROM public.databasechangelog_patients;")
                self.assertIn("39", history)
                role_sql("patients_runtime", env["PG_RUNTIME_TEST_PASSWORD"], "BEGIN;\n" + support +
                    (ROOT / "tooling/tests/backup_restore_permissions.sql").read_text())
            finally:
                env["PG_DATABASE"] = source
            self.assertEqual(fingerprint(recovered), expected, "Verification changed restored data or history")
            self.assertEqual(fingerprint(source), before, "Recovery changed the source database")
            self.assertEqual(run("docker", "exec", container, "sha256sum", archive), archive_digest)
            print(f"Backup/restore PASS: complete copy, runtime, unchanged history; drill {time.monotonic()-started:.1f}s", flush=True)

        def schema_count():
            return sql("SELECT count(*) FROM pg_namespace WHERE nspname = 'patients'")

        def synthetic_seed_checks():
            # patients-dml-synthetic-001 seeds two snapshots; patients-dml-synthetic-002 removes them again,
            # so dev/qa end without synthetic patients. Removal touches exact unchanged snapshots only.
            seed_ids = ("patients-dml-synthetic-001", "patients-dml-synthetic-002")
            history = "SELECT id,author,filename,md5sum,dateexecuted,orderexecuted FROM public.databasechangelog_patients"
            previous = sql(history + " ORDER BY orderexecuted")
            for extra in ((), ("--contexts=dev,prod",)):
                migrate("update", *extra, include_seeds=True, direct=True)
                self.assertEqual(sql(history + " ORDER BY orderexecuted"), previous)
                self.assertEqual(sql("SELECT count(*) FROM patients.patient"), "0")
            data = ("SELECT jsonb_build_object('profiles',(SELECT jsonb_agg(to_jsonb(p) ORDER BY patient_id) "
                "FROM patients.patient p),'contacts',(SELECT jsonb_agg(to_jsonb(c) ORDER BY emergency_contact_id) "
                "FROM patients.emergency_contact c))")
            def empty():
                self.assertEqual(sql("SELECT count(*) FROM patients.patient"), "0")
                self.assertEqual(sql("SELECT count(*) FROM patients.emergency_contact"), "0")
            migrate("update", include_seeds=True)
            expected = "39" if ENVIRONMENT in PRODUCTION else "41"
            self.assertEqual(sql("SELECT count(*) FROM public.databasechangelog_patients"), expected)
            empty()
            if ENVIRONMENT not in PRODUCTION:
                recorded = sql(history + " ORDER BY orderexecuted")
                kept = sql(history + " WHERE id<>'patients-dml-synthetic-002' ORDER BY orderexecuted")
                migrate("update", include_seeds=True)
                self.assertEqual(sql(history + " ORDER BY orderexecuted"), recorded)
                empty()
                # Rolling back the removal restores the exact snapshots for authenticated runtime reads.
                migrate("rollback-count", "--count=1", include_seeds=True)
                runtime_sql("BEGIN;\n" + (ROOT / "tooling/tests/synthetic_seeds.sql").read_text())
                seeded = sql(data)
                # An evolved snapshot blocks the removal and keeps both data and history.
                sql("UPDATE patients.patient SET address='Edited' WHERE patient_id='f2000000-0000-4000-8000-000000000002'")
                changed = sql(data)
                blocked = sql(history + " ORDER BY orderexecuted")
                rejected = migrate("update", include_seeds=True, check=False)
                self.assertNotEqual(rejected.returncode, 0, "Removal erased an evolved fixture")
                self.assertEqual(sql(data), changed)
                self.assertEqual(sql(history + " ORDER BY orderexecuted"), blocked)
                sql("UPDATE patients.patient SET address=NULL WHERE patient_id='f2000000-0000-4000-8000-000000000002'")
                self.assertEqual(sql(data), seeded)
                # Unrelated records survive the removal.
                sql_script(support + "SELECT pg_temp.register_patient(90,'CC','SEED-UNRELATED'); "
                    "INSERT INTO patients.emergency_contact VALUES ('20000000-0000-4000-8000-000000000090',"
                    "'00000000-0000-4000-8000-000000000090','Synthetic Other','Relative','3000000000');")
                unrelated = ("SELECT to_jsonb(p),to_jsonb(c) FROM patients.patient p "
                    "JOIN patients.emergency_contact c USING(patient_id) "
                    "WHERE patient_id='00000000-0000-4000-8000-000000000090'")
                other = sql(unrelated)
                migrate("update", include_seeds=True)
                self.assertEqual(sql(history + " WHERE id<>'patients-dml-synthetic-002' ORDER BY orderexecuted"), kept)
                self.assertEqual(sql("SELECT count(*) FROM public.databasechangelog_patients"), expected)
                self.assertEqual(sql("SELECT count(*) FROM patients.patient"), "1")
                self.assertEqual(sql("SELECT count(*) FROM patients.emergency_contact"), "1")
                self.assertEqual(sql(unrelated), other)
                # Both seed changes roll back to the pre-seed history without touching unrelated data.
                migrate("rollback-count", "--count=2", include_seeds=True)
                self.assertEqual(sql(history + " ORDER BY orderexecuted"), previous)
                self.assertEqual(sql(unrelated), other)
                sql("DELETE FROM patients.emergency_contact WHERE emergency_contact_id='20000000-0000-4000-8000-000000000090'")
                sql("DELETE FROM patients.patient WHERE patient_id='00000000-0000-4000-8000-000000000090'")
                migrate("update", include_seeds=True)
                empty()
            ids = ",".join("'" + seed + "'" for seed in seed_ids)
            self.assertEqual(sql(history + f" WHERE id NOT IN ({ids}) ORDER BY orderexecuted"), previous)
            self.assertEqual(sql("SELECT id FROM bootstrap_probe.marker"), "1")
            print("Synthetic seeds PASS: " + ENVIRONMENT, flush=True)

        config = json.loads(run("docker", "compose", "-f", str(compose),
                                "config", "--format", "json"))
        self.assertEqual(set(config["services"]), {"patients-db-migrate"})
        self.assertFalse(config.get("volumes"), "DB runner must not own volumes")
        run("docker", "network", "create", network)
        try:
            # Snapshot canonical migration files once; avoid repeated Windows bind-mount reads.
            run("docker", "volume", "create", snapshot)
            run("docker", "run", "--rm", "--entrypoint", "sh", "-v", f"{ROOT}:/source:ro",
                "-v", f"{snapshot}:/snapshot", POSTGRES_IMAGE, "-ec",
                "cp -R /source/01_ddl /source/02_dml /source/03_dcl /source/04_tcl "
                "/source/05_rollbacks /source/changelog /snapshot/ && mkdir /snapshot/deploy && "
                "cp /source/deploy/run-migration.sh /snapshot/deploy/")
            run("docker", "run", "-d", "--name", container, "--network", network,
                "-e", "POSTGRES_DB=" + env["PG_DATABASE"],
                "-e", "POSTGRES_PASSWORD=" + env["PG_MIGRATION_PASSWORD"],
                "--health-cmd", "pg_isready -U postgres -d patients_ci",
                "--health-interval", "1s", "--health-timeout", "3s",
                "--health-retries", "30", POSTGRES_IMAGE)
            run("docker", "run", "--rm", "--network", network,
                POSTGRES_IMAGE, "sh", "-ec",
                f"for i in $(seq 1 60); do pg_isready -q -t 1 -h {container} "
                "-U postgres -d patients_ci && exit 0; sleep 1; done; exit 1")
            sql("CREATE SCHEMA bootstrap_probe; "
                "CREATE TABLE bootstrap_probe.marker (id integer PRIMARY KEY); "
                "INSERT INTO bootstrap_probe.marker VALUES (1)")
            sql("CREATE SCHEMA query_extensions; CREATE EXTENSION pg_trgm WITH SCHEMA query_extensions")
            if ENVIRONMENT:
                environment_checks()
                if BACKUP_RESTORE:
                    backup_restore_checks()
                if SYNTHETIC_SEEDS:
                    synthetic_seed_checks()
                return
            sql("CREATE ROLE patients_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE "
                "NOREPLICATION NOBYPASSRLS PASSWORD '" + env["PG_RUNTIME_TEST_PASSWORD"] + "'")
            sql("CREATE ROLE patients_reader NOLOGIN; CREATE ROLE patients_writer NOLOGIN; "
                "GRANT patients_reader, patients_runtime TO patients_writer; "
                "CREATE ROLE patients_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE "
                "NOREPLICATION NOBYPASSRLS PASSWORD '" + env["PG_APP_TEST_PASSWORD"] + "'")
            migrate("validate")
            if SCHEMA_SMOKE:
                print("Schema smoke: empty-store migration and current storage checks", flush=True)
                migrate("update")
                storage_checks()
                runtime_checks()
                concurrent_identity_check()
                concurrent_idempotency_check()
                concurrent_outbox_claim_check()
                concurrent_inbox_check()
                concurrent_deactivation_check()
                return
            # Start from the already delivered bootstrap, preserving its history on upgrade.
            migrate("update-count", "--count=1")
            history = "public.databasechangelog_patients"
            bootstrap = sql(f"SELECT id, md5sum, dateexecuted FROM {history}")
            migrate("update", "--label-filter=!emergency-contacts and !patient-audit and !idempotency and !outbox and !inbox and !runtime and !deactivation-operations and !query-indexes")
            self.assertEqual(sql("SELECT to_regclass('patients.emergency_contacts') IS NULL"), "t")
            baseline_count = int(sql(f"SELECT count(*) FROM {history}"))
            prior_history_query = (f"SELECT id, md5sum, dateexecuted FROM {history} "
                                   f"WHERE orderexecuted <= {baseline_count} ORDER BY orderexecuted")
            prior_history = sql(prior_history_query)
            sql_script(legacy_support + "SELECT pg_temp.register_patient(90, 'CC', 'CONTACTS-UPGRADE');")
            patient_query = ("SELECT row_to_json(p)::text FROM patients.patients p "
                             "WHERE patient_id = '00000000-0000-4000-8000-000000000090'")
            prior_patient = sql(patient_query)
            migrate("update", "--label-filter=!patient-audit and !idempotency and !outbox and !inbox and !runtime and !deactivation-operations and !query-indexes")
            self.assertEqual(sql(patient_query), prior_patient)
            increment_count = int(sql(f"SELECT count(*) FROM {history}")) - baseline_count
            self.assertGreater(increment_count, 0)
            migrate("rollback-count", "--count=" + str(increment_count))
            self.assertEqual(sql("SELECT to_regclass('patients.emergency_contacts') IS NULL"), "t")
            self.assertEqual(sql(patient_query), prior_patient)
            migrate("update", "--label-filter=!patient-audit and !idempotency and !outbox and !inbox and !runtime and !deactivation-operations and !query-indexes")
            self.assertEqual(sql(patient_query), prior_patient)
            self.assertEqual(sql(prior_history_query), prior_history)
            # Upgrade from the delivered contacts schema, then reverse only the audit increment.
            audit_baseline = int(sql(f"SELECT count(*) FROM {history}"))
            old_history_query = (f"SELECT id, md5sum, dateexecuted FROM {history} "
                                 f"WHERE orderexecuted <= {audit_baseline} ORDER BY orderexecuted")
            old_history = sql(old_history_query)
            sql("INSERT INTO patients.emergency_contacts VALUES "
                "('20000000-0000-4000-8000-000000000090', "
                "'00000000-0000-4000-8000-000000000090', 'Synthetic Contact', 'Relative', '3000000000')")
            contact_query = ("SELECT row_to_json(c)::text FROM patients.emergency_contacts c WHERE "
                             "emergency_contact_id = '20000000-0000-4000-8000-000000000090'")
            prior_contact = sql(contact_query)
            self.assertEqual(sql("SELECT to_regclass('patients.patient_audit') IS NULL"), "t")
            migrate("update", "--label-filter=!idempotency and !outbox and !inbox and !runtime and !deactivation-operations and !query-indexes")
            self.assertEqual(sql(patient_query), prior_patient)
            self.assertEqual(sql(contact_query), prior_contact)
            audit_count = int(sql(f"SELECT count(*) FROM {history}")) - audit_baseline
            self.assertGreater(audit_count, 0)
            migrate("rollback-count", "--count=" + str(audit_count))
            self.assertEqual(sql("SELECT to_regclass('patients.patient_audit') IS NULL"), "t")
            self.assertEqual(sql(patient_query), prior_patient)
            self.assertEqual(sql(contact_query), prior_contact)
            migrate("update", "--label-filter=!idempotency and !outbox and !inbox and !runtime and !deactivation-operations and !query-indexes")
            self.assertEqual(sql(patient_query), prior_patient)
            self.assertEqual(sql(contact_query), prior_contact)
            self.assertEqual(sql(old_history_query), old_history)
            retry_baseline = int(sql(f"SELECT count(*) FROM {history}"))
            previous_query = (f"SELECT id, md5sum, dateexecuted FROM {history} "
                              f"WHERE orderexecuted <= {retry_baseline} ORDER BY orderexecuted")
            previous = sql(previous_query)
            migrate("update", "--label-filter=!outbox and !inbox and !runtime and !deactivation-operations and !query-indexes")
            retry_count = int(sql(f"SELECT count(*) FROM {history}")) - retry_baseline
            self.assertGreater(retry_count, 0)
            migrate("rollback-count", "--count=" + str(retry_count))
            self.assertEqual(sql("SELECT to_regclass('patients.idempotency_records') IS NULL"), "t")
            self.assertEqual(sql(patient_query), prior_patient)
            self.assertEqual(sql(contact_query), prior_contact)
            migrate("update", "--label-filter=!outbox and !inbox and !runtime and !deactivation-operations and !query-indexes")
            self.assertEqual(sql(previous_query), previous)
            outbox_baseline = int(sql(f"SELECT count(*) FROM {history}"))
            baseline_query = (f"SELECT id,md5sum,dateexecuted FROM {history} "
                              f"WHERE orderexecuted <= {outbox_baseline} ORDER BY orderexecuted")
            baseline_history = sql(baseline_query)
            migrate("update", "--label-filter=!inbox and !runtime and !deactivation-operations and !query-indexes")
            outbox_count = int(sql(f"SELECT count(*) FROM {history}")) - outbox_baseline
            self.assertGreater(outbox_count, 0)
            migrate("rollback-count", "--count=" + str(outbox_count))
            self.assertEqual(sql("SELECT to_regclass('patients.outbox_events') IS NULL"), "t")
            self.assertEqual(sql(patient_query), prior_patient)
            self.assertEqual(sql(contact_query), prior_contact)
            migrate("update", "--label-filter=!inbox and !runtime and !deactivation-operations and !query-indexes")
            self.assertEqual(sql(baseline_query), baseline_history)
            inbox_baseline = int(sql(f"SELECT count(*) FROM {history}"))
            inbox_history_query = (f"SELECT id,md5sum,dateexecuted FROM {history} "
                                   f"WHERE orderexecuted <= {inbox_baseline} ORDER BY orderexecuted")
            inbox_history = sql(inbox_history_query)
            migrate("update", "--label-filter=!runtime and !deactivation-operations and !query-indexes")
            inbox_count = int(sql(f"SELECT count(*) FROM {history}")) - inbox_baseline
            self.assertEqual(inbox_count, 4)
            migrate("rollback-count", "--count=" + str(inbox_count))
            self.assertEqual(sql("SELECT to_regclass('patients.inbox_events') IS NULL"), "t")
            self.assertEqual(sql(patient_query), prior_patient)
            self.assertEqual(sql(contact_query), prior_contact)
            migrate("update", "--label-filter=!runtime and !deactivation-operations and !query-indexes")
            self.assertEqual(sql(inbox_history_query), inbox_history)
            grants_baseline = int(sql(f"SELECT count(*) FROM {history}"))
            grants_query = (f"SELECT id,md5sum,dateexecuted FROM {history} "
                            f"WHERE orderexecuted <= {grants_baseline} ORDER BY orderexecuted")
            grants_history = sql(grants_query)
            runtime_denied()
            for change, restore in (
                ("ALTER ROLE patients_runtime RENAME TO patients_runtime_absent",
                 "ALTER ROLE patients_runtime_absent RENAME TO patients_runtime"),
                ("ALTER ROLE patients_runtime CREATEROLE", "ALTER ROLE patients_runtime NOCREATEROLE")):
                sql(change)
                try:
                    rejected = migrate("update", "--label-filter=!deactivation-operations and !query-indexes", check=False)
                    self.assertNotEqual(rejected.returncode, 0)
                    self.assertIn("precondition", (rejected.stdout + rejected.stderr).lower())
                finally:
                    sql(restore)
            migrate("update", "--label-filter=!deactivation-operations and !query-indexes")
            self.assertEqual(int(sql(f"SELECT count(*) FROM {history}")) - grants_baseline, 1)
            runtime_checks(legacy=True)
            migrate("rollback-count", "--count=1")
            runtime_denied()
            self.assertEqual(sql(patient_query), prior_patient)
            self.assertEqual(sql(contact_query), prior_contact)
            self.assertEqual(sql(grants_query), grants_history)
            migrate("update", "--label-filter=!deactivation-operations and !query-indexes")
            operation_baseline = int(sql(f"SELECT count(*) FROM {history}"))
            operation_history_query = (f"SELECT id,md5sum,dateexecuted FROM {history} "
                                       f"WHERE orderexecuted<={operation_baseline} ORDER BY orderexecuted")
            operation_history = sql(operation_history_query)
            migrate("update", "--label-filter=!query-indexes")
            self.assertEqual(int(sql(f"SELECT count(*) FROM {history}")) - operation_baseline, 6)
            migrate("rollback-count", "--count=6")
            self.assertEqual(sql("SELECT to_regclass('patients.deactivation_operations') IS NULL"), "t")
            self.assertEqual(sql(patient_query), prior_patient)
            self.assertEqual(sql(contact_query), prior_contact)
            self.assertEqual(sql(operation_history_query), operation_history)
            migrate("update", "--label-filter=!query-indexes")
            query_baseline = sql(f"SELECT id,md5sum,dateexecuted FROM {history} ORDER BY orderexecuted")
            sql("DROP EXTENSION pg_trgm")
            rejected = migrate("update", check=False)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("pg_trgm", rejected.stdout + rejected.stderr)
            self.assertEqual(query_index_count(), "0")
            self.assertEqual(sql(f"SELECT count(*) FROM {history}"), "33")
            sql("CREATE EXTENSION pg_trgm WITH SCHEMA query_extensions")
            extension = sql("SELECT oid,extnamespace FROM pg_extension WHERE extname='pg_trgm'")
            migrate("update")
            self.assertEqual(int(sql(f"SELECT count(*) FROM {history}")), 39)
            migrate("rollback-count", "--count=6")
            self.assertEqual(query_index_count(), "0")
            self.assertEqual(sql(patient_query), prior_patient)
            self.assertEqual(sql(contact_query), prior_contact)
            self.assertEqual(sql(f"SELECT id,md5sum,dateexecuted FROM {history} ORDER BY orderexecuted"), query_baseline)
            self.assertEqual(sql("SELECT oid,extnamespace FROM pg_extension WHERE extname='pg_trgm'"), extension)
            migrate("update")
            sql("DELETE FROM patients.emergency_contact WHERE "
                "emergency_contact_id = '20000000-0000-4000-8000-000000000090'")
            sql("DELETE FROM patients.patient WHERE "
                "patient_id = '00000000-0000-4000-8000-000000000090'")
            self.assertEqual(schema_count(), "1")
            self.assertEqual(sql(f"SELECT id, md5sum, dateexecuted FROM {history} "
                                 "WHERE id = 'patients-ddl-schema-001'"), bootstrap)
            storage_checks()
            runtime_checks()
            concurrent_identity_check()
            concurrent_idempotency_check()
            concurrent_outbox_claim_check()
            concurrent_inbox_check()
            concurrent_deactivation_check()
            recorded = sql(f"SELECT id, author, md5sum, dateexecuted "
                           f"FROM {history} ORDER BY orderexecuted")
            self.assertTrue(recorded, "No migration was recorded")
            migrate("update")
            self.assertEqual(sql(f"SELECT id, author, md5sum, dateexecuted "
                                 f"FROM {history} ORDER BY orderexecuted"), recorded)
            # migrate preflights every rollback, including historical increments.
            count = sql(f"SELECT count(*) FROM {history}")
            migrate("rollback-count", "--count=" + count)
            self.assertEqual(schema_count(), "0")
            self.assertEqual(sql("SELECT oid,extnamespace FROM pg_extension WHERE extname='pg_trgm'"), extension)
            self.assertEqual(sql(f"SELECT count(*) FROM {history}"), "0")
            migrate("update")
            self.assertEqual(schema_count(), "1")
            self.assertEqual(sql(f"SELECT count(*) FROM {history}"), count)
            storage_checks()
            runtime_checks()
            self.assertEqual(sql("SELECT id FROM bootstrap_probe.marker"), "1")
        except AssertionError:
            diagnostics = run("docker", "logs", container, check=False, return_result=True)
            print(redact(diagnostics.stdout + diagnostics.stderr), flush=True)
            raise
        finally:
            run("docker", "rm", "-fv", container, check=False)
            run("docker", "network", "rm", network, check=False)
            run("docker", "volume", "rm", snapshot, check=False)


if __name__ == "__main__":
    SYNTHETIC_SEEDS = "--synthetic-seeds" in sys.argv
    if SYNTHETIC_SEEDS:
        sys.argv.remove("--synthetic-seeds")
    BACKUP_RESTORE = "--backup-restore" in sys.argv
    if BACKUP_RESTORE:
        sys.argv.remove("--backup-restore")
    SCHEMA_SMOKE = "--schema-smoke" in sys.argv
    if SCHEMA_SMOKE:
        sys.argv.remove("--schema-smoke")
    ENVIRONMENT = next((arg.split("=", 1)[1] for arg in sys.argv if arg.startswith("--environment=")), None)
    if ENVIRONMENT is not None:
        sys.argv.remove("--environment=" + ENVIRONMENT)
    if BACKUP_RESTORE and (ENVIRONMENT != "dev" or SCHEMA_SMOKE):
        raise SystemExit("--backup-restore requires --environment=dev; it uses disposable databases only")
    if SYNTHETIC_SEEDS and (ENVIRONMENT not in ("dev", "qa", "main", "prod") or SCHEMA_SMOKE or BACKUP_RESTORE):
        raise SystemExit("--synthetic-seeds requires one environment and cannot combine with other focused modes")
    unittest.main(verbosity=2)
