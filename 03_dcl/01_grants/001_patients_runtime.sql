GRANT USAGE ON SCHEMA patients TO patients_runtime;
GRANT SELECT, INSERT ON patients.patients, patients.emergency_contacts, patients.patient_audit,
    patients.idempotency_records, patients.outbox_events, patients.inbox_events TO patients_runtime;
GRANT UPDATE (document_type,document_number,name,birth_date,phone,email,address,status,version,updated_at,updated_by)
    ON patients.patients TO patients_runtime;
GRANT UPDATE (name,relationship,phone) ON patients.emergency_contacts TO patients_runtime;
GRANT DELETE ON patients.emergency_contacts, patients.idempotency_records TO patients_runtime;
GRANT UPDATE (status,attempts,next_retry_at,error_code) ON patients.outbox_events TO patients_runtime;
GRANT UPDATE (status,attempts,next_retry_at,error_code) ON patients.inbox_events TO patients_runtime;
