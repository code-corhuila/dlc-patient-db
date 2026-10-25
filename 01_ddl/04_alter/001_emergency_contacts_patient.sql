ALTER TABLE patients.emergency_contacts
    ADD CONSTRAINT fk_emergency_contacts_patient FOREIGN KEY (patient_id)
    REFERENCES patients.patients (patient_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
