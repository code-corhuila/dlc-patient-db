ALTER TABLE patients.deactivation_operation ADD COLUMN reason_code text;
-- NOT VALID: new and updated rows must carry a code; no delivered environment holds operations yet.
ALTER TABLE patients.deactivation_operation ADD CONSTRAINT chk_deactivation_operation_reason_code
    CHECK (reason_code IS NOT NULL AND reason_code IN ('ADMINISTRATIVE','DUPLICATE_RECORD','PATIENT_REQUEST','OTHER')) NOT VALID;
CREATE FUNCTION patients.reject_reason_code_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION USING ERRCODE='23514',CONSTRAINT='chk_deactivation_operation_immutable',
        MESSAGE='Operation identity and facts are immutable';
END;
$$;
CREATE TRIGGER trg_deactivation_operation_reason_code
BEFORE UPDATE OF reason_code ON patients.deactivation_operation FOR EACH ROW
WHEN (OLD.reason_code IS DISTINCT FROM NEW.reason_code)
EXECUTE FUNCTION patients.reject_reason_code_change();
