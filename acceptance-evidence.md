# HU-PAT-001 owned persistence — acceptance evidence

Prepared 2026-11-03 (America/Bogota). Status: submitted for review, not accepted.
Refs: [dlc-patient-db#1](https://github.com/code-corhuila/dlc-patient-db/issues/1).
Related HU: [dlc-docs#53](https://github.com/code-corhuila/dlc-docs/issues/53).
The issue description supplied by the owner defines this delivery's scope.

## Revision and source of truth

- Inspected DB baseline: [4297e928f6fecbf11edf75fbddf4afc3a7500a67](https://github.com/code-corhuila/dlc-patient-db/commit/4297e928f6fecbf11edf75fbddf4afc3a7500a67), after PR #16.
- Executable rollback fix: [3e9d698f5b7af87f0b480b3b4931a0904827243e](https://github.com/code-corhuila/dlc-patient-db/commit/3e9d698f5b7af87f0b480b3b4931a0904827243e). Tooling, migrations, deployment and workflow trees match the baseline.
- Docs baseline: [31fb316d8209fbf1838feea9ecf0192c4b551585](https://github.com/code-corhuila/dlc-docs/commit/31fb316d8209fbf1838feea9ecf0192c4b551585). Apply PAT-001–005, ADR-003, migration strategy, DoD and quality gates as linked in [readiness](readiness.md).
- Three existing uncommitted search-contract/model drafts in Docs remain outside that pinned revision; paths and canonical-review limitation are recorded in readiness. They were not edited here.
- This branch changes documentation and PR traceability only. Its final commit SHA must be recorded in the PR after the owner commits; acceptance cannot be pre-recorded for an uncommitted revision.

## Issue acceptance matrix

Implementation paths below are relative to the pinned DB baseline. They identify
what is implemented and tested, not proof that a new execution or review occurred.

| Issue criterion | Implementation and executable checks | Evidence / remaining decision |
|---|---|---|
| Own administrative profile, normalized uniqueness, state, retained history and patient outbox | [Dictionary](data-dictionary.md); [identity](tooling/tests/patient_identity.sql), [contacts](tooling/tests/emergency_contacts.sql), [audit](tooling/tests/patient_audit.sql), [outbox](tooling/tests/outbox_events.sql) | PASS in the fresh full suite; [retained final validation](final-validation.md). Reviewer must accept the scoped result against the revision |
| Empty-store and previous-version migration; constraints, indexes and recovery | Single [master](changelog/changelog-master.yaml); historical increments/full rollback/rebuild in [verifier](tooling/verify_migrations.py); [index checks](tooling/tests/patient_query_indexes.sql); [restore procedure](backup-restore.md) | PASS: fresh full, environment and backup/restore runs; logs and hashes retained in final validation |
| Owner-only runtime/migration access; no unrelated schema or duplicate changelog changes | [Runtime negatives](tooling/tests/runtime_permissions.sql), [bootstrap](environment-bootstrap.md), foreign-owner preservation checks and authenticated migrator/runtime in verifier | PASS: fresh authenticated disposable checks for dev/qa/prod. Real infrastructure provisioning is outside this issue; deployment still requires operator evidence |
| PR records validation and unresolved decisions without claiming HU Done | This matrix, [readiness](readiness.md), [rollback diagnostics](rollback-verification.md) and [PR template](.github/pull_request_template.md) | Issue now linked. Final PR SHA, relevant output and existing review/approval links remain to be supplied in the PR |

Document normalization is `upper(btrim(...))` on both document fields, including
inactive profiles: preserves leading zeroes, punctuation and internal spaces.
No change is made to the approved PatientRegistered, PatientProfileUpdated or
PatientDeactivated event vocabulary. Storage checks do not prove producer delivery.

## Executed and reported results

The subsequent [complete final validation](final-validation.md) passed all nine
executions, including all eight Docker workflow scenarios. Its retained logs and
manifest supersede the earlier Docker-unavailable observation below. The historical
rows remain a record of earlier observations, not current test failures.

| Check | Revision / result | Evidence limit |
|---|---|---|
| Rollback regression suite, executed 2026-11-03 in this branch | DB baseline above, Python 3.12.14: 6 tests, 0.001s, OK | Fresh local execution; six cases listed below; no Docker required |
| Full disposable verification, prior development session | Rollback fix development tree, PASS 1295.912s | Historical session report, not a newly executed or independently accepted artifact; complete immutable output still needed |
| Synthetic seeds/dev, prior development session | Rollback fix development tree, PASS 552.283s | Same historical evidence limitation; protected failures and valid rollback/reapply covered |
| Backup/restore and other environment modes | Prior seed increment reports in readiness / PR #14 | Not rerun here; attach revision-linked retained results before accepting those claims |
| Earlier Docker availability check, 2026-11-03 | Linux engine pipe `dockerDesktopLinuxEngine` was missing | Resolved before final validation; all eight Docker scenarios subsequently ran successfully |
| Remote CI | Owner reports Actions budget exhausted | Operational blocker, not a repository defect or an approved CI waiver |

Fresh regression output summary (`python -B -m unittest discover -s tooling -p test_rollback_verification.py -v`):

```text
test_ambiguous_or_missing_history_cannot_start_rollback ... ok
test_chronological_history_executes_once_and_returns_result ... ok
test_command_failure_is_propagated_once_without_mislabeling_or_retry ... ok
test_equal_timestamps_and_history_order_gaps_are_valid ... ok
test_invalid_counts_cannot_start_rollback ... ok
test_observed_backwards_dates_block_even_a_single_change_rollback ... ok
Ran 6 tests in 0.001s
OK
```

The RED/GREEN history belongs to PR #16; this documentation increment introduces
no business logic and does not manufacture a new RED phase. Reproduction commands
for all eight configured Docker jobs remain in [readiness](readiness.md).
Use synthetic data only; attach sanitized output with command, tool versions,
source/Docs SHAs, dirty diff disclosure and exit result to the reviewed PR.

## Scoped closure and downstream handoff

Issue #1 prepares storage. API authorization, atomic application orchestration,
HTTP semantics, relay/consumer delivery and cross-service guard integration are
separate deliveries required for the HU; they are not waived or marked implemented.
IAM identity, Appointments eligibility/terminal-state guard and current relationship
remain integration dependencies. API, portal and technology-wide provisioning are
explicitly outside issue #1's implementation scope.

Before scoped closure, the PR/issue must link the final immutable revision, the
retained final-validation bundle and the independent review decision.
Existing PR approvals can supply that review when their reviewed SHA and evidence
are identified; no duplicate approval ceremony is introduced here.
The reviewer records accepted/pending criteria and unresolved decisions explicitly.

The owner has declined additional paid Actions execution. Current governance still
requires green CI: a local report alone cannot override that requirement. A change
or alternative needs the authorized project's recorded governance decision; none
is asserted by this branch. Keep the operational blocker visible without inventing
a code fix, disabling jobs or claiming remote success.

Canonical Docs synchronization, shared PostgreSQL sequence coordination and real
deployment/recovery evidence remain with the responsible owners in readiness.
Any Docs change uses its own governed PR; this branch does not modify that repository.
Closing this DB issue does not close HU-PAT-001 or authorize promotion/release.
There is no approved percentage rubric; no completion percentage is claimed.
