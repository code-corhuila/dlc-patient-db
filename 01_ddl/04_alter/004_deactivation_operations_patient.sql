ALTER TABLE patients.deactivation_operations ADD CONSTRAINT fk_deactivation_operations_patient
FOREIGN KEY (patient_id) REFERENCES patients.patients(patient_id) ON UPDATE RESTRICT ON DELETE RESTRICT;
