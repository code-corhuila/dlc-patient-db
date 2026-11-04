"""No database or Docker needed: each environment migrates only its own instance (Annex J.5)."""

from pathlib import Path
import unittest

ENV_DIR = Path(__file__).resolve().parents[1] / "deploy" / "env"
ENVIRONMENTS = ("dev", "qa", "main")


def read_example(environment):
    values = {}
    for line in (ENV_DIR / f"{environment}.env.example").read_text().splitlines():
        if line and not line.startswith("#"):
            key, _, value = line.partition("=")
            values[key] = value
    return values


class EnvironmentExamplesTest(unittest.TestCase):
    def test_each_environment_targets_its_own_instance(self):
        for environment in ENVIRONMENTS:
            with self.subTest(environment=environment):
                values = read_example(environment)
                self.assertEqual(values["PG_ENVIRONMENT"], environment)
                self.assertEqual(values["PG_HOST"], f"dlc-{environment}-dlc-postgres-1")
                self.assertEqual(values["COMPOSE_PROJECT_NAME"], f"patients-db-{environment}")
                self.assertIn(environment, values["PG_MIGRATOR_PASSWORD_FILE"])

    def test_no_two_environments_share_a_host_project_or_secret(self):
        for key in ("PG_HOST", "COMPOSE_PROJECT_NAME", "PG_MIGRATOR_PASSWORD_FILE"):
            with self.subTest(key=key):
                self.assertEqual(len({read_example(e)[key] for e in ENVIRONMENTS}), len(ENVIRONMENTS))

    def test_examples_carry_no_credentials(self):
        for environment in ENVIRONMENTS:
            with self.subTest(environment=environment):
                self.assertFalse({k for k in read_example(environment) if "PASSWORD" in k and not k.endswith("_FILE")})


if __name__ == "__main__":
    unittest.main()
