CREATE FUNCTION pg_temp.register_patient(n integer, kind text, number text) RETURNS uuid
LANGUAGE sql AS $$
    INSERT INTO patients.patients
        (patient_id, document_type, document_number, name, birth_date, phone, email,
         created_by, updated_by)
    VALUES (('00000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
            kind, number, 'Synthetic Patient', DATE '2000-01-01', '+57 3000000000',
            'patient@example.invalid', '10000000-0000-4000-8000-000000000001',
            '10000000-0000-4000-8000-000000000001') RETURNING patient_id;
$$;

CREATE FUNCTION pg_temp.expect_rejection(statement text, expected_code text, expected_name text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE code text; constraint_name text; column_name text;
BEGIN
    BEGIN
        EXECUTE statement;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS code = RETURNED_SQLSTATE,
            constraint_name = CONSTRAINT_NAME, column_name = COLUMN_NAME;
        IF code <> expected_code OR
           coalesce(nullif(constraint_name, ''), column_name) <> expected_name THEN
            RAISE;
        END IF;
        RETURN;
    END;
    RAISE EXCEPTION 'Expected rejection: % / %', expected_code, expected_name;
END;
$$;
