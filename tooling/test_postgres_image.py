"""No database or Docker needed: checks which PostgreSQL image the verifier starts."""

import unittest

from verify_migrations import postgres_image, schema_digest


class PostgresImageTest(unittest.TestCase):
    def test_default_is_the_infrastructure_engine(self):
        # dlc-infra-postgres compose.yml pins this engine for every environment.
        self.assertEqual(postgres_image({}), "postgres:17.11-alpine3.24")

    def test_pinned_override_is_used(self):
        self.assertEqual(postgres_image({"PATIENTS_POSTGRES_IMAGE": "postgres:16.6-alpine"}),
                         "postgres:16.6-alpine")

    def test_unpinned_or_foreign_images_are_rejected(self):
        for image in ("postgres", "postgres:latest", "postgres:17", "postgres:17-alpine",
                      "mysql:8.4.0", "evil/postgres:17.11-alpine3.24", " postgres:17.11-alpine3.24"):
            with self.subTest(image=image), self.assertRaises(ValueError):
                postgres_image({"PATIENTS_POSTGRES_IMAGE": image})


class SchemaDigestTest(unittest.TestCase):
    def dump(self, key, body="CREATE TABLE patients.patient ();\n"):
        return f"--\n\\restrict {key}\n\n{body}\n\\unrestrict {key}\n"

    def test_random_restrict_key_does_not_change_the_digest(self):
        # pg_dump 17.6+ writes a new random \restrict key on every run.
        self.assertEqual(schema_digest(self.dump("gmDro0BZju40")), schema_digest(self.dump("II4j8oRVoWbj")))

    def test_schema_changes_still_change_the_digest(self):
        self.assertNotEqual(schema_digest(self.dump("same")),
                            schema_digest(self.dump("same", "CREATE TABLE patients.other ();\n")))


if __name__ == "__main__":
    unittest.main()
