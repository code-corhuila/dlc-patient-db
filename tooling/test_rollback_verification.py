"""No database or Docker needed: the callback stands for the actual Liquibase command."""

from copy import deepcopy
import unittest
from unittest.mock import Mock

from rollback_verification import RollbackPreflightError, run_rollback


class RollbackVerificationTest(unittest.TestCase):
    def history(self):
        return [dict(id=f"change-{n}", orderexecuted=n,
                     dateexecuted=f"2026-11-03T04:16:01.{n:06d}") for n in (1, 2, 3)]

    def test_chronological_history_executes_once_and_returns_result(self):
        rows = self.history()
        before = deepcopy(rows)
        execute = Mock(return_value="Liquibase result")
        self.assertEqual(run_rollback(rows, 2, execute), "Liquibase result")
        execute.assert_called_once_with()
        self.assertEqual(rows, before)

    def test_equal_timestamps_and_history_order_gaps_are_valid(self):
        rows = self.history()
        rows[1]["dateexecuted"] = rows[0]["dateexecuted"]
        rows[2]["orderexecuted"] = 8
        execute = Mock()
        run_rollback(list(reversed(rows)), 3, execute)
        execute.assert_called_once_with()

    def test_command_failure_is_propagated_once_without_mislabeling_or_retry(self):
        error = ValueError("Command failure")
        execute = Mock(side_effect=error)
        with self.assertRaises(ValueError) as observed:
            run_rollback(self.history(), 1, execute)
        self.assertIs(observed.exception, error)
        self.assertNotIsInstance(observed.exception, RollbackPreflightError)
        execute.assert_called_once_with()

    def test_observed_backwards_dates_block_even_a_single_change_rollback(self):
        rows = self.history()
        rows[0]["dateexecuted"] = "2026-11-03T04:16:01.4331"
        rows[1]["dateexecuted"] = "2026-11-03T04:16:01.073861"
        before = deepcopy(rows)
        execute = Mock()
        with self.assertRaisesRegex(ValueError, "Non-monotonic.*change-1.*change-2"):
            run_rollback(rows, 1, execute)
        execute.assert_not_called()
        self.assertEqual(rows, before)

    def test_invalid_counts_cannot_start_rollback(self):
        for count in (0, -1, 4, True):
            with self.subTest(count=count):
                execute = Mock()
                with self.assertRaises(ValueError):
                    run_rollback(self.history(), count, execute)
                execute.assert_not_called()

    def test_ambiguous_or_missing_history_cannot_start_rollback(self):
        for change in ({"orderexecuted": 1}, {"dateexecuted": None}, {"dateexecuted": "invalid"}):
            with self.subTest(change=change):
                rows = self.history()
                rows[1].update(change)
                execute = Mock()
                with self.assertRaises(ValueError):
                    run_rollback(rows, 1, execute)
                execute.assert_not_called()
        execute = Mock()
        with self.assertRaises(ValueError):
            run_rollback([], 1, execute)
        execute.assert_not_called()


if __name__ == "__main__":
    unittest.main()
