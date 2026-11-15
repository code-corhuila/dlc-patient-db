CREATE FUNCTION patients.protect_patient_audit() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.recorded_at := statement_timestamp();
        RETURN NEW;
    END IF;
    RAISE EXCEPTION USING ERRCODE = '23514', CONSTRAINT = 'ck_patient_audit_append_only',
        MESSAGE = 'Patient audit is append-only';
END;
$$;
