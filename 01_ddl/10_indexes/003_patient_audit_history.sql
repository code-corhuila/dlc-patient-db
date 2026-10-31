CREATE INDEX idx_patient_audit_patient_recorded_at ON patients.patient_audit
    (patient_id, recorded_at, audit_id);
