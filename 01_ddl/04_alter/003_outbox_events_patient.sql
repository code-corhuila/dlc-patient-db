ALTER TABLE patients.outbox_events ADD CONSTRAINT fk_outbox_events_patient
    FOREIGN KEY (aggregate_id) REFERENCES patients.patients (patient_id)
    ON UPDATE RESTRICT ON DELETE RESTRICT;
