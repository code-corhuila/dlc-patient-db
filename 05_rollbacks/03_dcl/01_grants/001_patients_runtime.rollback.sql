REVOKE USAGE ON SCHEMA patients FROM patients_runtime;
REVOKE SELECT, INSERT ON patients.patients, patients.emergency_contacts, patients.patient_audit,
    patients.idempotency_records, patients.outbox_events, patients.inbox_events FROM patients_runtime;
REVOKE UPDATE (document_type,document_number,name,birth_date,phone,email,address,status,version,updated_at,updated_by)
    ON patients.patients FROM patients_runtime;
REVOKE UPDATE (name,relationship,phone) ON patients.emergency_contacts FROM patients_runtime;
REVOKE DELETE ON patients.emergency_contacts, patients.idempotency_records FROM patients_runtime;
REVOKE UPDATE (status,attempts,next_retry_at,error_code) ON patients.outbox_events FROM patients_runtime;
REVOKE UPDATE (status,attempts,next_retry_at,error_code) ON patients.inbox_events FROM patients_runtime;
