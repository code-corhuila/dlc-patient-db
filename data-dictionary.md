# Patients identity storage — HU-PAT-001 / PAT-001

Canonical model and boundaries: [Patients data model](https://github.com/code-corhuila/dlc-docs/blob/main/09-microservices/services/03-patients-service/data-model.md),
[modeling conventions](https://github.com/code-corhuila/dlc-docs/blob/main/06-data/modeling-conventions.md)
and [HTTP contract](https://github.com/code-corhuila/dlc-docs/blob/main/07-api/contracts/openapi/patients-service.yaml).
This dictionary maps the implemented storage increment; it does not replace dlc-docs.

| Column in `patients.patients` | Type | Storage rule |
|---|---|---|
| patient_id | uuid | Required primary key supplied by the API; immutable after insertion |
| document_type | text | Required, nonblank, at most 30 characters |
| document_number | text | Required, nonblank, at most 50 characters; leading zeroes preserved |
| name | text | Required, nonblank, at most 255 characters |
| birth_date | date | Required finite date strictly before CURRENT_DATE |
| phone | text | Required, nonblank, at most 40 characters; semantic phone validation belongs to API |
| email | text | Required, at most 255 characters; basic nonwhitespace local@domain.suffix structure |
| address | text | Nullable; when provided, nonblank and at most 500 characters |
| status | text | ACTIVE by default; CHECK permits only ACTIVE or INACTIVE |
| version | integer | Positive, defaults to 1; atomic expectedVersion updates belong to API |
| created_at / updated_at | timestamptz | Required; default to the transaction timestamp |
| created_by / updated_by | uuid | Required actor references; API derives them from authorized identity |

## Emergency contacts — HU-PAT-001

`patients.emergency_contacts` belongs to the same administrative aggregate.

| Column | Type | Storage rule |
|---|---|---|
| emergency_contact_id | uuid | Required primary key supplied by the API |
| patient_id | uuid | Required local reference to patients.patients |
| name | text | Required, nonblank, at most 255 characters |
| relationship | text | Required, nonblank, at most 80 characters; no closed catalog is specified |
| phone | text | Required, nonblank, at most 40 characters; semantic phone validation belongs to API |

A patient can have zero or multiple contacts; matching names or phone numbers are
not treated as duplicate identities. `fk_emergency_contacts_patient` rejects orphans
and uses ON UPDATE RESTRICT / ON DELETE RESTRICT; it never cascades patient deletion.
`idx_emergency_contacts_patient_id` supports the reference and contact lookup.
Changing patient status does not remove contacts. This does not replace API authorization,
the guarded deactivation protocol or the pending runtime privilege restrictions.

## Document equality

Owner clarification approved on 2026-10-24: equality uses `upper(btrim(value))`
on both document fields. This trims ordinary spaces at the edges and ignores case,
while preserving leading zeroes, punctuation and internal spaces.
The unique expression index `uk_patients_document` covers every status and
serializes conflicting inserts; it does not rewrite the supplied display values.
Document types remain text because dlc-docs defines no closed type catalog.

## Limits of this increment

Actor references have no foreign keys into IAM. There are no cross-schema queries,
clinical fields or financial fields. Identifier protection is a local trigger;
normal profile changes remain available without changing patient_id.
Runtime privileges, authoritative deactivation and append-only audit are separate
increments. Column defaults do not authenticate actors or prevent audit tampering.
SQL constraints complement application/domain validation; they do not authorize access.
