"""Rebuild only Patients in a disposable PostgreSQL database; requires Docker."""

import json
import os
from pathlib import Path
import secrets
import subprocess
import time
import unittest
import uuid


ROOT = Path(__file__).resolve().parents[1]


class MigrationRebuildTest(unittest.TestCase):
    def test_update_repeat_rollback_and_reapply_preserve_other_owners(self):
        compose = ROOT / "deploy" / "compose.yml"
        self.assertTrue(compose.is_file(), "Patients migration runner is missing")
        suffix = uuid.uuid4().hex[:12]
        network = f"patients-ci-{suffix}"
        snapshot = f"{network}-migrations"
        container = f"patients-postgres-{suffix}"
        env = dict(os.environ, PG_HOST=container, PG_PORT="5432",
                   PG_DATABASE="patients_ci", PG_MIGRATION_USER="postgres",
                   PG_MIGRATION_PASSWORD=secrets.token_hex(24), PG_NETWORK=network)

        def run(*args, check=True, input_text=None, return_result=False):
            try:
                result = subprocess.run(args, cwd=ROOT, env=env, text=True,
                                        capture_output=True, timeout=180, input=input_text)
            except subprocess.TimeoutExpired:
                self.fail("Docker command exceeded 180 seconds; check engine/registry access")
            if check and result.returncode:
                # Credentials must not appear in failure diagnostics.
                output = (result.stdout + result.stderr).replace(
                    env["PG_MIGRATION_PASSWORD"], "[REDACTED]")
                self.fail(output)
            return result if return_result else result.stdout.strip()

        psql = ["docker", "exec", container, "psql", "-U", "postgres",
                "-d", env["PG_DATABASE"], "-v", "ON_ERROR_STOP=1", "-Atc"]

        def sql(statement):
            return run(*psql, statement)

        support = (ROOT / "tooling/tests/support.sql").read_text()

        def sql_script(script):
            run("docker", "exec", "-i", container, "psql", "-U", "postgres",
                "-d", env["PG_DATABASE"], "-v", "ON_ERROR_STOP=1",
                input_text=script)

        def storage_checks():
            for name in ("patient_identity", "emergency_contacts", "patient_audit", "idempotency_records"):
                print("Storage checks: " + name, flush=True)
                sql_script("BEGIN;\n" + support + (ROOT / f"tooling/tests/{name}.sql").read_text())

        def concurrent_identity_check():
            def insert(n, kind, number):
                return ("INSERT INTO patients.patients (patient_id, document_type, "
                        "document_number, name, birth_date, phone, email, created_by, updated_by) "
                        f"VALUES ('00000000-0000-4000-8000-{n:012d}', '{kind}', '{number}', "
                        "'Synthetic Race', '2000-01-01', '3000000000', 'race@example.invalid', "
                        "'10000000-0000-4000-8000-000000000001', "
                        "'10000000-0000-4000-8000-000000000001'); ")

            concurrent_insert_check(insert(10, 'CC', 'RACE-01'), insert(11, ' cc ', ' race-01 '),
                                    'uk_patients_document')
            self.assertEqual(sql("SELECT count(*) FROM patients.patients"), "1")

        def concurrent_insert_check(first_insert, second_insert, constraint):
            first = subprocess.Popen([*psql, "SET application_name = 'patients-race'; "
                "BEGIN; " + first_insert + "SELECT pg_sleep(8); COMMIT;"],
                cwd=ROOT, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                for _ in range(40):
                    if sql("SELECT count(*) FROM pg_stat_activity WHERE "
                           "application_name = 'patients-race' AND wait_event = 'PgSleep'") == "1":
                        break
                    self.assertIsNone(first.poll(), "First transaction ended before the race")
                    time.sleep(0.1)
                else:
                    self.fail("First transaction did not reach its uncommitted insert")
                second = run(*psql, second_insert,
                             check=False, return_result=True)
                self.assertNotEqual(second.returncode, 0)
                self.assertIn(constraint, second.stderr)
            finally:
                _, error = first.communicate(timeout=30)
            self.assertEqual(first.returncode, 0, error)

        def concurrent_idempotency_check():
            statement = ("INSERT INTO patients.idempotency_records (actor_kind, actor_subject, operation, "
                "target_resource, idempotency_key, request_hash, response_status, response_body) VALUES "
                "('SERVICE','patients-ci','register','/patients','40000000-0000-4000-8000-000000000010',"
                "repeat('a',64),201,'{}'); ")
            concurrent_insert_check(statement, statement, 'pk_idempotency_records')
            self.assertEqual(sql("SELECT count(*) FROM patients.idempotency_records"), "1")

        def migrate(*args):
            print("Liquibase: " + " ".join(args), flush=True)
            return run("docker", "compose", "-p", network, "-f", str(compose),
                       "run", "--rm", "-v", f"{snapshot}:/workspace:ro", "patients-db-migrate", *args)

        def schema_count():
            return sql("SELECT count(*) FROM pg_namespace WHERE nspname = 'patients'")

        config = json.loads(run("docker", "compose", "-f", str(compose),
                                "config", "--format", "json"))
        self.assertEqual(set(config["services"]), {"patients-db-migrate"})
        self.assertFalse(config.get("volumes"), "DB runner must not own volumes")
        run("docker", "network", "create", network)
        try:
            # Snapshot canonical migration files once; avoid repeated Windows bind-mount reads.
            run("docker", "volume", "create", snapshot)
            run("docker", "run", "--rm", "--entrypoint", "sh", "-v", f"{ROOT}:/source:ro",
                "-v", f"{snapshot}:/snapshot", "postgres:16.6-alpine", "-ec",
                "cp -R /source/01_ddl /source/02_dml /source/03_dcl /source/04_tcl "
                "/source/05_rollbacks /source/changelog /snapshot/")
            run("docker", "run", "-d", "--name", container, "--network", network,
                "-e", "POSTGRES_DB=" + env["PG_DATABASE"],
                "-e", "POSTGRES_PASSWORD=" + env["PG_MIGRATION_PASSWORD"],
                "--health-cmd", "pg_isready -U postgres -d patients_ci",
                "--health-interval", "1s", "--health-timeout", "3s",
                "--health-retries", "30", "postgres:16.6-alpine")
            run("docker", "run", "--rm", "--network", network,
                "postgres:16.6-alpine", "sh", "-ec",
                f"for i in $(seq 1 60); do pg_isready -q -t 1 -h {container} "
                "-U postgres -d patients_ci && exit 0; sleep 1; done; exit 1")
            sql("CREATE SCHEMA bootstrap_probe; "
                "CREATE TABLE bootstrap_probe.marker (id integer PRIMARY KEY); "
                "INSERT INTO bootstrap_probe.marker VALUES (1)")
            migrate("validate")
            # Start from the already delivered bootstrap, preserving its history on upgrade.
            migrate("update-count", "--count=1")
            history = "public.databasechangelog_patients"
            bootstrap = sql(f"SELECT id, md5sum, dateexecuted FROM {history}")
            migrate("update", "--label-filter=!emergency-contacts and !patient-audit and !idempotency")
            self.assertEqual(sql("SELECT to_regclass('patients.emergency_contacts') IS NULL"), "t")
            baseline_count = int(sql(f"SELECT count(*) FROM {history}"))
            prior_history_query = (f"SELECT id, md5sum, dateexecuted FROM {history} "
                                   f"WHERE orderexecuted <= {baseline_count} ORDER BY orderexecuted")
            prior_history = sql(prior_history_query)
            sql_script(support + "SELECT pg_temp.register_patient(90, 'CC', 'CONTACTS-UPGRADE');")
            patient_query = ("SELECT row_to_json(p)::text FROM patients.patients p "
                             "WHERE patient_id = '00000000-0000-4000-8000-000000000090'")
            prior_patient = sql(patient_query)
            migrate("update", "--label-filter=!patient-audit and !idempotency")
            self.assertEqual(sql(patient_query), prior_patient)
            increment_count = int(sql(f"SELECT count(*) FROM {history}")) - baseline_count
            self.assertGreater(increment_count, 0)
            migrate("rollback-count", "--count=" + str(increment_count))
            self.assertEqual(sql("SELECT to_regclass('patients.emergency_contacts') IS NULL"), "t")
            self.assertEqual(sql(patient_query), prior_patient)
            migrate("update", "--label-filter=!patient-audit and !idempotency")
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
            migrate("update", "--label-filter=!idempotency")
            self.assertEqual(sql(patient_query), prior_patient)
            self.assertEqual(sql(contact_query), prior_contact)
            audit_count = int(sql(f"SELECT count(*) FROM {history}")) - audit_baseline
            self.assertGreater(audit_count, 0)
            migrate("rollback-count", "--count=" + str(audit_count))
            self.assertEqual(sql("SELECT to_regclass('patients.patient_audit') IS NULL"), "t")
            self.assertEqual(sql(patient_query), prior_patient)
            self.assertEqual(sql(contact_query), prior_contact)
            migrate("update", "--label-filter=!idempotency")
            self.assertEqual(sql(patient_query), prior_patient)
            self.assertEqual(sql(contact_query), prior_contact)
            self.assertEqual(sql(old_history_query), old_history)
            retry_baseline = int(sql(f"SELECT count(*) FROM {history}"))
            previous_query = (f"SELECT id, md5sum, dateexecuted FROM {history} "
                              f"WHERE orderexecuted <= {retry_baseline} ORDER BY orderexecuted")
            previous = sql(previous_query)
            migrate("update")
            retry_count = int(sql(f"SELECT count(*) FROM {history}")) - retry_baseline
            self.assertGreater(retry_count, 0)
            migrate("rollback-count", "--count=" + str(retry_count))
            self.assertEqual(sql("SELECT to_regclass('patients.idempotency_records') IS NULL"), "t")
            self.assertEqual(sql(patient_query), prior_patient)
            self.assertEqual(sql(contact_query), prior_contact)
            migrate("update")
            self.assertEqual(sql(previous_query), previous)
            sql("DELETE FROM patients.emergency_contacts WHERE "
                "emergency_contact_id = '20000000-0000-4000-8000-000000000090'")
            sql("DELETE FROM patients.patients WHERE "
                "patient_id = '00000000-0000-4000-8000-000000000090'")
            self.assertEqual(schema_count(), "1")
            self.assertEqual(sql(f"SELECT id, md5sum, dateexecuted FROM {history} "
                                 "WHERE id = 'patients-ddl-schema-001'"), bootstrap)
            storage_checks()
            concurrent_identity_check()
            concurrent_idempotency_check()
            recorded = sql(f"SELECT id, author, md5sum, dateexecuted "
                           f"FROM {history} ORDER BY orderexecuted")
            self.assertTrue(recorded, "No migration was recorded")
            migrate("update")
            self.assertEqual(sql(f"SELECT id, author, md5sum, dateexecuted "
                                 f"FROM {history} ORDER BY orderexecuted"), recorded)
            count = sql(f"SELECT count(*) FROM {history}")
            migrate("rollback-count", "--count=" + count)
            self.assertEqual(schema_count(), "0")
            self.assertEqual(sql(f"SELECT count(*) FROM {history}"), "0")
            migrate("update")
            self.assertEqual(schema_count(), "1")
            self.assertEqual(sql(f"SELECT count(*) FROM {history}"), count)
            storage_checks()
            self.assertEqual(sql("SELECT id FROM bootstrap_probe.marker"), "1")
        except AssertionError:
            diagnostics = run("docker", "logs", container, check=False, return_result=True)
            print((diagnostics.stdout + diagnostics.stderr).replace(
                env["PG_MIGRATION_PASSWORD"], "[REDACTED]"), flush=True)
            raise
        finally:
            run("docker", "rm", "-fv", container, check=False)
            run("docker", "network", "rm", network, check=False)
            run("docker", "volume", "rm", snapshot, check=False)


if __name__ == "__main__":
    unittest.main(verbosity=2)
