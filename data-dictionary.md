# Patients administrative storage — HU-PAT-001 / PAT-001

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

## Patient audit — HU-PAT-001

`patients.patient_audit` retains administrative facts with these storage fields:

| Column | Type | Storage rule |
|---|---|---|
| audit_id | uuid | Immutable primary key supplied by the API |
| patient_id | uuid | Required local patient reference; ON UPDATE/DELETE RESTRICT |
| actor_id | uuid | Required IAM actor reference without a cross-schema foreign key |
| action | text | REGISTERED, PROFILE_UPDATED or DEACTIVATED; local audit vocabulary |
| patient_version | integer | Required positive profile version; API must correlate the owning write |
| recorded_at | timestamptz | Always replaced with statement_timestamp() by the insert trigger |
| changed_fields | text[] | Required one-dimensional array of approved administrative field names; defaults to empty |
| reason | text | Nullable except for DEACTIVATED; when present, nonblank and at most 1000 characters |

Metadata permits only documentType, documentNumber, name, birthDate, phone, email,
address, emergencyContacts and status. It stores no profile snapshots or arbitrary
clinical payload. Reasons remain protected owner data; callers must minimize their content.
The history index starts with patient_id, then recorded_at and audit_id.
UPDATE, DELETE and TRUNCATE are rejected, including a cascading parent TRUNCATE.
This is explicit audit storage, not automatic auditing of every profile write.
The API must supply an authorized actor and write profile/audit/outbox atomically.
Runtime grants and retention operations remain separate work; no purge is introduced.

## Idempotency records — HU-PAT-001

This storage mapping implements the scope/retention rules in
[API design decisions](https://github.com/code-corhuila/dlc-docs/blob/main/07-api/design-decisions.md#idempotency-and-optimistic-updates).
`patients.idempotency_records` stores completed outcomes, not pending guard intents.

| Column | Type | Storage rule |
|---|---|---|
| actor_kind | text | STAFF or SERVICE, derived from the authenticated principal |
| actor_subject | text | Canonical verified subject, nonblank, at most 255 characters |
| operation | text | Canonical owner operation identifier, nonblank, at most 100 characters |
| target_resource | text | Canonical resource scope, nonblank, at most 255 characters; creation uses the collection scope |
| idempotency_key | uuid | Retry key; the primary key includes all four scope fields above |
| request_hash | text | SHA-256 digest of the canonical request, 64 lowercase hexadecimal characters |
| response_status / response_body | smallint / jsonb | Original status (200–599) and JSON object; no raw request body is stored |
| response_location | text | Optional original Location; nonblank when supplied, without CR/LF |
| created_at / expires_at | timestamptz | Server-stamped creation and finite expiry at least 168 hours later |

Staff subjects use the canonical staff UUID string; service subjects use their verified
service identity. The API must derive/canonicalize the complete scope, hash the same
request representation on retries, and compare hashes before returning saved results
or IDEMPOTENCY_CONFLICT. It must reauthenticate and reauthorize every retry.
Saved response bodies may contain administrative PII and remain protected Patients data.
Records cannot be updated or truncated; deletion is allowed only after expiry.
The expiry index supports bounded cleanup, but this increment configures no purge job.
The service must commit the result with its owning write/audit/outbox in one transaction;
database transaction tests are not evidence that API orchestration is implemented.
Expiration neither releases coordination guards nor removes permanent document uniqueness.

## Outbox events — HU-PAT-001

`patients.outbox_events` maps the [Patients event contracts](https://github.com/code-corhuila/dlc-docs/blob/main/09-microservices/services/03-patients-service/events.md).

| Columns | Storage rule |
|---|---|
| event_id | Immutable UUID primary key, reused on every delivery attempt |
| aggregate_id / aggregate_type | Required local patient UUID reference, ON UPDATE/DELETE RESTRICT; type is Patient |
| event_type / event_version / producer | PatientRegistered, PatientProfileUpdated or PatientDeactivated; schema version 1; patients-service |
| occurred_at / recorded_at | Finite fact instant and server-stamped recording instant, both timestamptz |
| payload | Required JSON object, matching patientId and exactly the required payload keys for its event type |
| correlation_id / causation_id / actor_user_id | Correlation and causation UUIDs required; actor UUID nullable under the envelope contract |
| status / attempts | Initially PENDING / 0; PENDING, FAILED and PUBLISHED are local publication states; attempts never decreases |
| next_retry_at / published_at | Pending work requires a finite retry instant; published work gets a server-stamped marker and no retry instant |
| error_code | Optional uppercase code (at most 100 characters), required for FAILED; no free-form driver details |

Facts, payload and tracing identifiers cannot change. DELETE/TRUNCATE are rejected;
no history-purge policy is invented. FAILED may be reconciled to PENDING, while PUBLISHED
is terminal. Counters/backoff limits and broker confirmation belong to the future relay.
The pending partial index supports bounded `FOR UPDATE SKIP LOCKED` claims; an additional
aggregate index supports the local foreign key. Concurrent claim checks verify row locks,
not broker delivery, exactly-once processing or global business ordering.
Full JSON Schema validation, event serialization, owner-side authorization and atomic
profile/audit/outbox orchestration remain producer/application work. The publisher must
mark PUBLISHED only after broker confirmation; a crash may cause same-event redelivery.
Consumers still require Inbox deduplication, and current patient/guard contracts remain authoritative.

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
Runtime privileges, authoritative deactivation and atomic business/audit/outbox writes
are separate increments. Profile defaults do not authenticate actors; audit triggers
protect ordinary DML but do not replace restrictions on DDL-capable migration credentials.
SQL constraints complement application/domain validation; they do not authorize access.
