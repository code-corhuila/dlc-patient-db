CREATE TRIGGER trg_patient_audit_write
BEFORE INSERT OR UPDATE OR DELETE ON patients.patient_audit FOR EACH ROW
EXECUTE FUNCTION patients.protect_patient_audit();
CREATE TRIGGER trg_patient_audit_truncate
BEFORE TRUNCATE ON patients.patient_audit FOR EACH STATEMENT
EXECUTE FUNCTION patients.protect_patient_audit();
