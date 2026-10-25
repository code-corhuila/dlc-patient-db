CREATE TRIGGER trg_patients_identity_immutable
BEFORE UPDATE OF patient_id ON patients.patients FOR EACH ROW
WHEN (NEW.patient_id IS NOT NULL AND OLD.patient_id IS DISTINCT FROM NEW.patient_id)
EXECUTE FUNCTION patients.reject_patient_id_change();
