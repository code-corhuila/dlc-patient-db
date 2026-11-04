REVOKE patients_writer FROM patients_app;
REVOKE SELECT ON patients.patient, patients.emergency_contact FROM patients_reader;
REVOKE USAGE ON SCHEMA patients FROM patients_reader;
