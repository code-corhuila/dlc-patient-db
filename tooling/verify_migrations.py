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

        def identity_checks():
            run("docker", "exec", "-i", container, "psql", "-U", "postgres",
                "-d", env["PG_DATABASE"], "-v", "ON_ERROR_STOP=1",
                input_text=(ROOT / "tooling/tests/patient_identity.sql").read_text())

        def concurrent_identity_check():
            def insert(n, kind, number):
                return ("INSERT INTO patients.patients (patient_id, document_type, "
                        "document_number, name, birth_date, phone, email, created_by, updated_by) "
                        f"VALUES ('00000000-0000-4000-8000-{n:012d}', '{kind}', '{number}', "
                        "'Synthetic Race', '2000-01-01', '3000000000', 'race@example.invalid', "
                        "'10000000-0000-4000-8000-000000000001', "
                        "'10000000-0000-4000-8000-000000000001'); ")

            first = subprocess.Popen([*psql, "SET application_name = 'patients-race'; "
                "BEGIN; " + insert(10, 'CC', 'RACE-01') + "SELECT pg_sleep(8); COMMIT;"],
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
                second = run(*psql, insert(11, ' cc ', ' race-01 '),
                             check=False, return_result=True)
                self.assertNotEqual(second.returncode, 0)
                self.assertIn('uk_patients_document', second.stderr)
            finally:
                _, error = first.communicate(timeout=30)
            self.assertEqual(first.returncode, 0, error)
            self.assertEqual(sql("SELECT count(*) FROM patients.patients"), "1")

        def migrate(*args):
            print("Liquibase: " + " ".join(args), flush=True)
            return run("docker", "compose", "-p", network, "-f", str(compose),
                       "run", "--rm", "patients-db-migrate", *args)

        def schema_count():
            return sql("SELECT count(*) FROM pg_namespace WHERE nspname = 'patients'")

        config = json.loads(run("docker", "compose", "-f", str(compose),
                                "config", "--format", "json"))
        self.assertEqual(set(config["services"]), {"patients-db-migrate"})
        self.assertFalse(config.get("volumes"), "DB runner must not own volumes")
        run("docker", "network", "create", network)
        try:
            run("docker", "run", "-d", "--name", container, "--network", network,
                "-e", "POSTGRES_DB=" + env["PG_DATABASE"],
                "-e", "POSTGRES_PASSWORD=" + env["PG_MIGRATION_PASSWORD"],
                "--health-cmd", "pg_isready -U postgres -d patients_ci",
                "--health-interval", "1s", "--health-timeout", "3s",
                "--health-retries", "30", "postgres:16.6-alpine")
            run("docker", "run", "--rm", "--network", network,
                "postgres:16.6-alpine", "sh", "-ec",
                f"for i in $(seq 1 30); do pg_isready -h {container} "
                "-U postgres -d patients_ci && exit 0; sleep 1; done; exit 1")
            sql("CREATE SCHEMA bootstrap_probe; "
                "CREATE TABLE bootstrap_probe.marker (id integer PRIMARY KEY); "
                "INSERT INTO bootstrap_probe.marker VALUES (1)")
            migrate("validate")
            # Start from the already delivered bootstrap, preserving its history on upgrade.
            migrate("update-count", "--count=1")
            history = "public.databasechangelog_patients"
            bootstrap = sql(f"SELECT id, md5sum, dateexecuted FROM {history}")
            migrate("update")
            self.assertEqual(schema_count(), "1")
            self.assertEqual(sql(f"SELECT id, md5sum, dateexecuted FROM {history} "
                                 "WHERE id = 'patients-ddl-schema-001'"), bootstrap)
            identity_checks()
            concurrent_identity_check()
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
            identity_checks()
            self.assertEqual(sql("SELECT id FROM bootstrap_probe.marker"), "1")
        finally:
            run("docker", "rm", "-fv", container, check=False)
            run("docker", "network", "rm", network, check=False)


if __name__ == "__main__":
    unittest.main(verbosity=2)
