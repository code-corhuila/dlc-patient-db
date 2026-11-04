GRANT USAGE ON SCHEMA patients TO patients_reader;
GRANT SELECT ON patients.patient, patients.emergency_contact TO patients_reader;
GRANT patients_writer TO patients_app;
