CREATE FUNCTION patients.reject_patient_id_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION USING ERRCODE = '23514',
        CONSTRAINT = 'ck_patients_identity_immutable',
        MESSAGE = 'Patient identifier is immutable';
END;
$$;
