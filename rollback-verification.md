# Rollback verification preflight

Source: dlc-docs migration strategy and Patients runbook. Applied SQL is unchanged;
the guard only reads history. Real recovery remains forward-corrective.
This change concerns the disposable verifier, not production deployment commands.

The historical idempotency rollback previously tried to drop its table before
its index. A separate disposable fixture showed DATEEXECUTED going backwards as
ORDEREXECUTED increased. The original complete failing history was unavailable;
those observations do not establish a permanent host/VM/database root cause.
The old chronology guard ran only before the final full rollback, too late to
protect earlier incremental reversals.

`migrate` now reads the actual owner-specific history and preflights every
rollback-count before starting the Liquibase container, including seed reversals.
It prints migration identity, author, file, execution order and timestamp for
diagnosis. It validates the count and a unique positive execution order, parses
timestamps, and rejects a date regression. Equal timestamps are valid because
ORDEREXECUTED breaks ties; gaps in execution order are allowed.
On rejection, the rollback callback is never invoked, even when the caller expects
a SQL failure. This prevents a broken clock from passing a negative SQL test.
The check runs in uniquely named isolated test databases with no competing migrator;
it is not a locking protocol or a deployment-safe history-repair mechanism.

Run the regression tests without Docker:

```sh
python -B -m unittest discover -s tooling -p test_rollback_verification.py -v
```

Then run the normal Docker suite in isolation:

```sh
python -B tooling/verify_migrations.py
```

Regression tests reproduce the observed backwards fractional timestamps and require
zero callback calls and unchanged input. Positive cases verify one execution and
unchanged history, including equal dates and sequence gaps. Invalid counts, missing
dates and duplicate orders must fail before execution. Command failures propagate
without retry and remain distinct from preflight failures. CI runs these tests before
the complete migration suite.
The Actions-budget blocker remains an operational item.

If a live fixture is rejected, retain the printed history and failing command/result,
inspect host/VM/database clock and timestamp recording, and correct the cause before
rerunning. Do not rewrite DATEEXECUTED, add IF EXISTS to hide wrong rollback order,
disable constraints, edit applied SQL or retry until a run happens to pass.
A successful isolated run verifies that run, not permanent clock stability.
