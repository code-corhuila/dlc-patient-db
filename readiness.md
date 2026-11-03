# Patients DB readiness review

Review date: 2026-11-02 (America/Bogota). Scope: dlc-patient-db, HU-PAT-001.
**Decision: pending acceptance; not ready for promotion or operational release.**
This is an evidence inventory and handoff, not reviewer approval or a new project policy.

## Revisions and authority

DB baseline: [91ed1218314d095b1e19883bf67a41655427d670](https://github.com/code-corhuila/dlc-patient-db/commit/91ed1218314d095b1e19883bf67a41655427d670),
merged from [PR #14](https://github.com/code-corhuila/dlc-patient-db/pull/14).
Its tree matches seed head aa04bae8d3c10e98df5d9b21e92eed0d5c29cf31.
This branch adds review documentation only; its eventual commit must be reviewed separately.

The inspected dlc-docs baseline is 31fb316d8209fbf1838feea9ecf0192c4b551585:

- [Quality gates](https://github.com/code-corhuila/dlc-docs/blob/31fb316d8209fbf1838feea9ecf0192c4b551585/00-governance/quality-gates.md) and [DoD](https://github.com/code-corhuila/dlc-docs/blob/31fb316d8209fbf1838feea9ecf0192c4b551585/00-governance/definition-of-done.md).
- [HU-PAT-001](https://github.com/code-corhuila/dlc-docs/blob/31fb316d8209fbf1838feea9ecf0192c4b551585/04-requirements/user-stories.md), [PAT-001 to PAT-005](https://github.com/code-corhuila/dlc-docs/blob/31fb316d8209fbf1838feea9ecf0192c4b551585/02-domain/entities-and-rules.md) and [traceability](https://github.com/code-corhuila/dlc-docs/blob/31fb316d8209fbf1838feea9ecf0192c4b551585/04-requirements/traceability-matrix.md).
- [Migration strategy](https://github.com/code-corhuila/dlc-docs/blob/31fb316d8209fbf1838feea9ecf0192c4b551585/06-data/migration-strategy.md) and [Patients runbook](https://github.com/code-corhuila/dlc-docs/blob/31fb316d8209fbf1838feea9ecf0192c4b551585/09-microservices/services/03-patients-service/runbook.md).

The local dlc-docs working tree also has uncommitted search clarifications in
`07-api/contracts/openapi/patients-service.yaml`, `07-api/contract-reviews/patients.md`
and `09-microservices/services/03-patients-service/data-model.md`, on
`codex/patient-search-contract`. They are owner-provided draft context, not part of
the pinned commit or proof of canonical review. This review leaves them untouched.
Reconcile them with the canonical Docs PR/revision and record approval through a
governed docs/* -> main flow before accepting search; local changes do not prove remote status.
The dated repository-evidence register's earlier 404 observations do not prove absence
of the DB implementation now inspected; update that register via a separate Docs PR.

## Storage coverage and acceptance boundaries

The following paths identify implemented checks; execution evidence is recorded separately.
The canonical [master changelog](changelog/changelog-master.yaml) contains 34 structural/
permission changesets plus one explicitly non-production seed. There are seven owner tables.
The [dictionary](data-dictionary.md) maps their fields; no clinical or financial tables belong here.

| Requirement / concern | DB evidence | Remaining acceptance evidence |
|---|---|---|
| PAT-001: stable ID, normalized document uniqueness across statuses | [Identity checks](tooling/tests/patient_identity.sql); concurrent duplicate inserts in [verifier](tooling/verify_migrations.py) | API derives actors, validates input and maps duplicate conflicts correctly |
| HU-PAT-001: zero/multiple emergency contacts | [Contact checks](tooling/tests/emergency_contacts.sql), local restricted FK | Authorized aggregate create/update and API contract tests |
| PAT-002: only active patients receive new appointments/care | ACTIVE/INACTIVE storage and [deactivation records](tooling/tests/deactivation_operations.sql) | Appointments/Clinical admission, authoritative status and concurrency tests |
| PAT-003: administrative roles and scoped Dentist reads | [Technical runtime grants](runtime-permissions.md), [authenticated checks](tooling/tests/runtime_permissions.sql) | Real JWT/role/assignment authorization, negative list/search/detail cases and minimized projections |
| PAT-004: audited reason and guarded deactivation | [Audit checks](tooling/tests/patient_audit.sql), durable intent/guard fingerprint/outcome checks | Administrator-only use case, authoritative Appointments guard, unavailable-dependency and scheduling races |
| PAT-005: retain history | Restricted local references, immutable journals, inactive/contact retention and denied runtime profile deletion | Cross-owner history preservation and end-to-end guarded deactivation; no automatic appointment cancellation |
| Atomic profile/audit/outbox | [Audit transaction probes](tooling/tests/patient_audit.sql), [outbox rollback probes](tooling/tests/outbox_events.sql) | One application transaction with optimistic expectedVersion and durable operation outcome |
| HTTP replay | [Idempotency checks](tooling/tests/idempotency_records.sql), scoped keys, immutable response and retention | Authorization before replay, request-hash conflicts, HTTP status/response behavior |
| Lifecycle and assignment integration | [Outbox](tooling/tests/outbox_events.sql), [inbox](tooling/tests/inbox_events.sql), deduplication and disjoint claims | Broker relay, consumer/provider contracts, retries, reconciliation and unknown outcomes |
| Search, status and stable pages | [Query plans and SQL cases](tooling/tests/patient_query_indexes.sql), [limits/prerequisites](query-indexes.md) | Canonical search clarification, API adapter, current authorization before count/page and target workload evidence |
| Least privilege and environment bootstrap | [Bootstrap procedure](environment-bootstrap.md), owner/context/secret and foreign-access checks | Actual infrastructure roles, secrets, ownership inventory and effective privileges |
| Recovery | [Backup/restore drill](backup-restore.md) and authenticated restored-runtime checks | Protected real backups, restore observation, cluster/role recovery, cross-owner reconciliation and measured recovery objectives |
| Synthetic data isolation | [Seed checks](tooling/tests/synthetic_seeds.sql), [scope/rollback](synthetic-seeds.md) | Environment configuration verified by operator; synthetic snapshots are not real use-case facts |
| Release security | Pinned PostgreSQL/Liquibase images in the deployment/verifier files | No image-security scan is configured in this workflow; retain applicable security findings and resolution before release |

The adjacent local API repository at 9c4518fa289a46c6ec500780f0d0f1c3c8c6f978
contains README.md only. This is a local snapshot, not a claim about all remote refs.
Missing API/provider behavior stays pending; technical DB grants do not implement business roles.

## Executed evidence

The prior increment recorded local seed dev/qa/prod and backup/restore successes in
the development session and PR #14 description. The description is a report, not a
retained test artifact or independent DoD decision. Attach revision-bound output.

| Revision / check | Observed result | Evidence limit |
|---|---|---|
| Seed head aa04bae; [CI run 41575547105, attempt 1](https://github.com/code-corhuila/dlc-patient-db/actions/runs/41575547105) | FAILURE: all eight jobs | Job metadata shows no executed steps, runner_id 0, blank runner name; no test execution can be inferred |
| Three requested job logs from that run | Unavailable: BlobNotFound | No log-based diagnosis; see the owner's subsequent Actions-budget clarification below |
| DB baseline 91ed121; full local verifier during this review | FAIL after 435.398s at historical idempotency rollback | Table rollback preceded its index rollback; DROP INDEX then reported idx_idempotency_records_expires_at missing. Full rollback/rebuild was not reached |
| Same executable baseline; local --environment=prod | PASS, 398.550s; storage, indexes, ownership and authenticated grants | Disposable fixture only; non-monotonic history was separately observed. This mode does not verify full rollback |

PR #14 is merged, but its body still contains `code-corhuila/dlc-docs#NN` and an
unchecked remote-CI item. Merge/issue closure is not acceptance. The connector query
for the merge SHA returned no PR-triggered runs; that filtered result does not prove
absence of all possible workflow events. No workflow rerun or remote write was performed.

Owner clarification, 2026-11-03: Actions execution is blocked because the project has
exhausted its paid Actions budget. This is owner-reported operational context, not an
independent inspection of billing settings. No repository CI fix is planned for this
cause. Restore execution capacity or obtain a project-approved alternative; local
success does not replace the required CI gate or authorize acceptance.

### Local rollback diagnostic

The executable/migration/deployment tree is unchanged from the pinned DB baseline;
the working diff contains review documentation only. The following read-only query
was executed in the separate prod-labelled disposable fixture, not a real environment:

```sql
SELECT id, orderexecuted, dateexecuted, previous
FROM (
    SELECT id, orderexecuted, dateexecuted,
           lag(dateexecuted) OVER (ORDER BY orderexecuted) AS previous
    FROM public.databasechangelog_patients
) h
WHERE dateexecuted < previous;
```

Observed rows (UTC timestamp values):

```text
patients-ddl-functions-001|11|2026-11-03 04:16:01.073861|2026-11-03 04:16:01.4331
patients-ddl-functions-003|13|2026-11-03 04:16:00.982195|2026-11-03 04:16:01.127516
```

This confirms a non-monotonic recorded history in that fixture. The verifier already
checks chronology before its final full rollback; the failed run stopped earlier,
during an incremental rollback. Liquibase sorts rollback by DATEEXECUTED, then
ORDEREXECUTED. The failed fixture's complete pre-rollback history was not retained,
so the precise cause of that failure is not established by these separate rows.
Investigate host/VM/database clock behavior and timestamp recording, retain a fresh
failing history and rerun sequentially after correcting the cause. Do not rewrite
history dates, edit applied SQL, hide missing-index errors or treat a repeat as acceptance.

## Reproduce and attach evidence

Use Python 3.12+ and Linux Docker. These commands create disposable synthetic databases;
environment names in test arguments are not real deployment targets. Run sequentially
when collecting a local review bundle to avoid resource contention.

```sh
git rev-parse HEAD
git status --short
python -B tooling/verify_migrations.py
python -B tooling/verify_migrations.py --environment=dev
python -B tooling/verify_migrations.py --environment=qa
python -B tooling/verify_migrations.py --environment=prod
python -B tooling/verify_migrations.py --environment=dev --backup-restore
python -B tooling/verify_migrations.py --environment=dev --synthetic-seeds
python -B tooling/verify_migrations.py --environment=qa --synthetic-seeds
python -B tooling/verify_migrations.py --environment=prod --synthetic-seeds
git diff --check
```

The [CI workflow](.github/workflows/ci.yml) defines these eight jobs. The full suite
covers empty-store, delivered-version upgrades, immutable history, individual/full
rollback, rebuild, storage invariants, permissions and concurrency. A schema-smoke
run is narrower and cannot substitute for it. Base/recovery suites exclude the seed;
seed jobs require 35 recorded changesets in dev/qa and 34 with no seed in prod.

For each acceptance row, record exact source and Docs SHAs, any dirty diff, command,
environment/tool versions, result and retained log/artifact or CI job URL. Historical
results do not certify a new revision. Keep secrets/real patient contents out of evidence.
For documentation-only work, validate references and consistency; new business logic
must retain RED -> GREEN -> REFACTOR evidence. Do not manufacture RED tests for prose.

## Open handoff and release gates

| ID | Responsible role | Concrete next evidence |
|---|---|---|
| R-01 | Repository/Actions administrator and DB owner | Address the owner-reported Actions-budget blocker and obtain all eight successful jobs for the reviewed revision, or document a project-approved alternative; retain the failed-run trail |
| R-02 | Patients/Docs owner and required Docs reviewer | Reconcile/review the canonical search clarification, replace #NN with a real issue, link the evidence matrix and refresh the dated repository-evidence register via docs/* -> main |
| R-03 | DB and shared PostgreSQL owners | Coordinate actual include order/changeset identity against all owners' changelogs and deployed history; document ownership transitions without editing applied migrations |
| R-04 | Infrastructure operator and DB owner | Bind isolated endpoints/secrets, provision compatible pg_trgm and migrator namespace access, seal CREATE, verify effective grants and indexes, record migration/restore observations |
| R-05 | Patients API owner and affected service owners | Implement and verify the application/authorization/HTTP/event/guard behavior listed above; register linked issues without marking missing implementation N/A |
| R-06 | Tech Lead/Docs owner | Resolve authoritative branching-policy qa/* versus git-conventions promotion/* discrepancy before promotion; preserve mandatory cherry-pick -x provenance |
| R-07 | Independent team reviewer / authorized board maintainer | Record explicit DoD decision for the immutable revision and evidence; only then may the authorized maintainer update Done |
| R-08 | DB owner and local/infrastructure operator | Resolve the local incremental rollback failure and non-monotonic recorded timestamps; retain the offending history and a successful full upgrade/rollback/rebuild run after diagnosis |

No High/Critical security release block can be waived. Security findings, application
compatibility, real recovery and target-environment verification remain required before
release. Whole-schema rollback is confined to disposable tests; shared-environment
recovery follows reviewed forward corrections. Main still requires ariel5253 approval.
Do not change protections, skip failing jobs or infer Done from a percentage or CI status.
This branch neither approves promotion nor publishes external issues/reviews.
