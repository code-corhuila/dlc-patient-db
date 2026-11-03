"""Preflight of the disposable verifier's recorded rollback order."""

from datetime import datetime


class RollbackPreflightError(ValueError):
    """Recorded history cannot safely be passed to Liquibase rollback."""


def run_rollback(history, count, execute):
    if type(count) is not int or not 0 < count <= len(history):
        raise RollbackPreflightError("Rollback count must be positive and within the recorded history")
    try:
        ordered = sorted(history, key=lambda row: row["orderexecuted"])
        timestamps = [datetime.fromisoformat(row["dateexecuted"]) for row in ordered]
        orders = [row["orderexecuted"] for row in ordered]
        if any(type(order) is not int or order <= 0 for order in orders) or len(set(orders)) != len(orders):
            raise ValueError("Ambiguous execution order")
    except (KeyError, TypeError, ValueError) as error:
        raise RollbackPreflightError(f"Invalid migration history: {error}") from error
    for i in range(1, len(ordered)):
        try:
            backwards = timestamps[i] < timestamps[i - 1]
        except TypeError as error:
            raise RollbackPreflightError("Inconsistent timestamp timezones in migration history") from error
        if backwards:
            left, right = ordered[i - 1], ordered[i]
            raise RollbackPreflightError(f"Non-monotonic migration clock: {left['id']} ({left['dateexecuted']}) "
                             f"precedes {right['id']} ({right['dateexecuted']}); retain history and inspect clocks")
    return execute()
