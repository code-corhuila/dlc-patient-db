ALTER TABLE patients.patient_audit ADD CONSTRAINT fk_patient_audit_patient
    FOREIGN KEY (patient_id) REFERENCES patients.patients (patient_id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;
