SELECT pg_temp.register_patient(1, 'CC', '00ab-12.3 4');
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM patients.patient WHERE status = 'ACTIVE' AND version = 1
                   AND address IS NULL AND created_at = updated_at) THEN
        RAISE EXCEPTION 'Registration defaults are invalid';
    END IF;
END;
$$;
SELECT pg_temp.expect_rejection($q$SELECT pg_temp.register_patient(2, ' cc ', ' 00AB-12.3 4 ')$q$,
                                '23505', 'uk_patient_document');
UPDATE patients.patient SET status = 'INACTIVE';
SELECT pg_temp.expect_rejection($q$SELECT pg_temp.register_patient(2, 'CC', '00ab-12.3 4')$q$,
                                '23505', 'uk_patient_document');
SELECT pg_temp.expect_rejection($q$SELECT pg_temp.register_patient(1, 'OTHER', 'other')$q$,
                                '23505', 'pk_patient');
SELECT pg_temp.expect_rejection($q$UPDATE patients.patient
    SET patient_id = '00000000-0000-4000-8000-000000000099'$q$,
    '23514', 'chk_patient_identity_immutable');
-- Different types, leading zeroes and internal separators remain distinct.
SELECT pg_temp.register_patient(2, 'OTHER', '00ab-12.3 4');
SELECT pg_temp.register_patient(3, 'CC', '0ab-12.3 4');
SELECT pg_temp.register_patient(4, 'CC', '00ab1234');
SELECT pg_temp.register_patient(5, 'CC', '00ab-12.34');
-- Maximum contract lengths and nullable address remain accepted.
UPDATE patients.patient SET document_type = repeat('T', 30), document_number = repeat('0', 50),
    name = repeat('N', 255), phone = repeat('1', 40), email = repeat('e', 245) || '@x.invalid',
    address = repeat('A', 500), version = 2
WHERE patient_id = '00000000-0000-4000-8000-000000000005';
DO $$
DECLARE field text; sample record;
BEGIN
    IF (SELECT count(*) FROM patients.patient) <> 5 THEN
        RAISE EXCEPTION 'Distinct identities were merged';
    END IF;
    FOREACH field IN ARRAY ARRAY['patient_id', 'document_type', 'document_number', 'name',
        'birth_date', 'phone', 'email', 'status', 'version', 'created_at', 'updated_at',
        'created_by', 'updated_by'] LOOP
        PERFORM pg_temp.expect_rejection(format('UPDATE patients.patient SET %I = NULL', field),
                                        '23502', field);
    END LOOP;
    FOR sample IN SELECT * FROM (VALUES
        ('document_type', $q$' '$q$, 'chk_patient_document_type'),
        ('document_type', $q$repeat('C', 31)$q$, 'chk_patient_document_type'),
        ('document_number', $q$' '$q$, 'chk_patient_document_number'),
        ('document_number', $q$repeat('1', 51)$q$, 'chk_patient_document_number'),
        ('name', $q$' '$q$, 'chk_patient_name'),
        ('name', $q$E'\t\n'$q$, 'chk_patient_name'),
        ('name', $q$repeat('N', 256)$q$, 'chk_patient_name'),
        ('phone', $q$' '$q$, 'chk_patient_phone'),
        ('phone', $q$repeat('1', 41)$q$, 'chk_patient_phone'),
        ('email', $q$'invalid'$q$, 'chk_patient_email'),
        ('email', $q$'a b@example.invalid'$q$, 'chk_patient_email'),
        ('email', $q$repeat('e', 250) || '@x.invalid'$q$, 'chk_patient_email'),
        ('address', $q$' '$q$, 'chk_patient_address'),
        ('address', $q$repeat('A', 501)$q$, 'chk_patient_address'),
        ('status', $q$'DELETED'$q$, 'chk_patient_status'),
        ('version', '0', 'chk_patient_version'),
        ('version', '-1', 'chk_patient_version'),
        ('birth_date', 'CURRENT_DATE', 'chk_patient_birth_date'),
        ('birth_date', 'CURRENT_DATE + 1', 'chk_patient_birth_date'),
        ('birth_date', $q$'-infinity'::date$q$, 'chk_patient_birth_date'),
        ('birth_date', $q$'infinity'::date$q$, 'chk_patient_birth_date')
    ) AS cases(field, expression, constraint_name) LOOP
        PERFORM pg_temp.expect_rejection(format('UPDATE patients.patient SET %I = %s',
            sample.field, sample.expression), '23514', sample.constraint_name);
    END LOOP;
END;
$$;
ROLLBACK;
