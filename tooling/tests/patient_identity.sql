SELECT pg_temp.register_patient(1, 'CC', '00ab-12.3 4');
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM patients.patients WHERE status = 'ACTIVE' AND version = 1
                   AND address IS NULL AND created_at = updated_at) THEN
        RAISE EXCEPTION 'Registration defaults are invalid';
    END IF;
END;
$$;
SELECT pg_temp.expect_rejection($q$SELECT pg_temp.register_patient(2, ' cc ', ' 00AB-12.3 4 ')$q$,
                                '23505', 'uk_patients_document');
UPDATE patients.patients SET status = 'INACTIVE';
SELECT pg_temp.expect_rejection($q$SELECT pg_temp.register_patient(2, 'CC', '00ab-12.3 4')$q$,
                                '23505', 'uk_patients_document');
SELECT pg_temp.expect_rejection($q$SELECT pg_temp.register_patient(1, 'OTHER', 'other')$q$,
                                '23505', 'pk_patients');
SELECT pg_temp.expect_rejection($q$UPDATE patients.patients
    SET patient_id = '00000000-0000-4000-8000-000000000099'$q$,
    '23514', 'ck_patients_identity_immutable');
-- Different types, leading zeroes and internal separators remain distinct.
SELECT pg_temp.register_patient(2, 'OTHER', '00ab-12.3 4');
SELECT pg_temp.register_patient(3, 'CC', '0ab-12.3 4');
SELECT pg_temp.register_patient(4, 'CC', '00ab1234');
SELECT pg_temp.register_patient(5, 'CC', '00ab-12.34');
-- Maximum contract lengths and nullable address remain accepted.
UPDATE patients.patients SET document_type = repeat('T', 30), document_number = repeat('0', 50),
    name = repeat('N', 255), phone = repeat('1', 40), email = repeat('e', 245) || '@x.invalid',
    address = repeat('A', 500), version = 2
WHERE patient_id = '00000000-0000-4000-8000-000000000005';
DO $$
DECLARE field text; sample record;
BEGIN
    IF (SELECT count(*) FROM patients.patients) <> 5 THEN
        RAISE EXCEPTION 'Distinct identities were merged';
    END IF;
    FOREACH field IN ARRAY ARRAY['patient_id', 'document_type', 'document_number', 'name',
        'birth_date', 'phone', 'email', 'status', 'version', 'created_at', 'updated_at',
        'created_by', 'updated_by'] LOOP
        PERFORM pg_temp.expect_rejection(format('UPDATE patients.patients SET %I = NULL', field),
                                        '23502', field);
    END LOOP;
    FOR sample IN SELECT * FROM (VALUES
        ('document_type', $q$' '$q$, 'ck_patients_document_type'),
        ('document_type', $q$repeat('C', 31)$q$, 'ck_patients_document_type'),
        ('document_number', $q$' '$q$, 'ck_patients_document_number'),
        ('document_number', $q$repeat('1', 51)$q$, 'ck_patients_document_number'),
        ('name', $q$' '$q$, 'ck_patients_name'),
        ('name', $q$E'\t\n'$q$, 'ck_patients_name'),
        ('name', $q$repeat('N', 256)$q$, 'ck_patients_name'),
        ('phone', $q$' '$q$, 'ck_patients_phone'),
        ('phone', $q$repeat('1', 41)$q$, 'ck_patients_phone'),
        ('email', $q$'invalid'$q$, 'ck_patients_email'),
        ('email', $q$'a b@example.invalid'$q$, 'ck_patients_email'),
        ('email', $q$repeat('e', 250) || '@x.invalid'$q$, 'ck_patients_email'),
        ('address', $q$' '$q$, 'ck_patients_address'),
        ('address', $q$repeat('A', 501)$q$, 'ck_patients_address'),
        ('status', $q$'DELETED'$q$, 'ck_patients_status'),
        ('version', '0', 'ck_patients_version'),
        ('version', '-1', 'ck_patients_version'),
        ('birth_date', 'CURRENT_DATE', 'ck_patients_birth_date'),
        ('birth_date', 'CURRENT_DATE + 1', 'ck_patients_birth_date'),
        ('birth_date', $q$'-infinity'::date$q$, 'ck_patients_birth_date'),
        ('birth_date', $q$'infinity'::date$q$, 'ck_patients_birth_date')
    ) AS cases(field, expression, constraint_name) LOOP
        PERFORM pg_temp.expect_rejection(format('UPDATE patients.patients SET %I = %s',
            sample.field, sample.expression), '23514', sample.constraint_name);
    END LOOP;
END;
$$;
ROLLBACK;
