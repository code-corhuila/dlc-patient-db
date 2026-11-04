DROP TRIGGER trg_deactivation_operation_proof ON patients.deactivation_operation;
DROP TRIGGER trg_patient_deactivation_proof ON patients.patient;
DROP FUNCTION patients.require_deactivation_proof() RESTRICT;
