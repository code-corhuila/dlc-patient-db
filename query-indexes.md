# Patients query indexes

Source: dlc-docs Patients OpenAPI, owner data model and search clarification of 2026-11-02
(companion branch codex/patient-search-contract). Contract approval and API tests remain required.

| Index | Supported path |
|---|---|
| idx_patients_created_at_patient_id | Stable createdAt/id ascending pages without status |
| idx_patients_status_created_at_patient_id | Status equality followed by the same stable order |
| idx_patients_name_document_search | Multicolumn GIN on lower(name), lower(document_number), using pg_trgm |

Administrative search is a literal substring in name OR document number. Lowercase the
term, preserve accents/spaces/punctuation, and escape backslash, % and _ before adding
surrounding % wildcards. Bind values as parameters. Do not concatenate fields or include
phone/email/document type. Dentist search uses name only and the current owner-authorized
identifier scope; never reuse the administrative document predicate for care searches.
Apply trusted scope, status and search before counts/pages. Use separate query shapes for
optional filters, and always order by created_at, patient_id. The existing normalized
unique document index still enforces identity equality; these indexes do not replace it.

Before changeset patients-ddl-indexes-008, infrastructure must provision pg_trgm, verify
its gin_trgm_ops operator class and grant namespace USAGE to patients_migrator. Record the
actual extension owner, namespace and version. The migration discovers the class namespace
and membership from catalogs; it never creates/moves/drops an extension or grants global
access. query_extensions is only a disposable fixture name, not a production requirement.
Rollback removes only these three Patients indexes, preserving extension and prior history.

Verification uses 20,000 synthetic records, a 2% inactive distribution and timestamp ties.
After ANALYZE and an administrative GIN pending-list flush for the bulk fixture, EXPLAIN
(ANALYZE, BUFFERS, FORMAT JSON) runs under patients_runtime. Tests require naturally selected
ordered B-tree plans and a selective GIN path; no planner method is disabled. Common status
filters may choose either ordered B-tree. Counts, scoped ties/offsets, empty pages, case,
accents, one-character terms, literal wildcard handling and excluded contact fields are checked.
Short/common searches may use sequential scans; deep OFFSET and arbitrary scopes still cost
work. There is no application adapter or production latency guarantee. GIN write/maintenance
costs, real query parameters/statistics and prepared plans require target-environment evidence.
Transactional CREATE INDEX can block writes: review locking/backfill and recovery before live
execution. These migrations do not claim concurrent online DDL or deploy any environment.

References: [pg_trgm](https://www.postgresql.org/docs/16/pgtrgm.html),
[multicolumn indexes](https://www.postgresql.org/docs/16/indexes-multicolumn.html).
