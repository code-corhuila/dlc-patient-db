## User story

Refs: code-corhuila/dlc-docs#NN (replace with the actual issue)
Requirement: HU-PAT-001; state the implemented increment and remaining criteria.

## What changes and why

## How it was tested

Link the reviewed revision, RED/GREEN evidence and CI result.
Map affected acceptance criteria to executed checks; declare pending checks.

## Promotion trail

For develop: N/A. For qa/main: include each `cherry picked from commit` trail.

## Checklist

- [ ] Changes follow the Patients specifications in dlc-docs.
- [ ] Schema changes reside only in dlc-patient-db; applied changesets are immutable.
- [ ] Constraints, indexes and rollbacks are included where applicable.
- [ ] No secrets, real patient data or cross-owner writes are included.
- [ ] Tests and CI evidence are attached; green CI is not automatic DoD acceptance.
- [ ] The entire PR is at most 400 added/deleted lines, including tests and docs.
- [ ] Commits follow Conventional Commits; CODEOWNERS is preserved.
