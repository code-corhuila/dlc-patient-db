"""No Docker needed: the repository keeps the ci.yml entry point that Norma 5.1 and Annex I require."""

from pathlib import Path
import unittest

WORKFLOWS = Path(__file__).resolve().parents[1] / ".github" / "workflows"


class WorkflowsTest(unittest.TestCase):
    def test_ci_runs_unit_tests_on_every_permanent_branch_pull_request(self):
        ci = (WORKFLOWS / "ci.yml").read_text()
        self.assertIn("branches: [develop, qa, main]", ci)
        self.assertIn("workflow_dispatch:", ci)
        self.assertIn("contents: read", ci)
        self.assertIn("timeout-minutes: 10", ci)
        self.assertIn('-p "test_*.py"', ci)

    def test_rebuild_verification_stays_in_db_ci(self):
        db_ci = (WORKFLOWS / "db-ci.yml").read_text()
        self.assertIn("python -B tooling/verify_migrations.py", db_ci)


if __name__ == "__main__":
    unittest.main()
