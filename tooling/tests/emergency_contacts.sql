SELECT pg_temp.register_patient(1, 'CC', 'CONTACTS-01');
SELECT pg_temp.register_patient(2, 'CC', 'CONTACTS-02');
INSERT INTO patients.emergency_contact
    (emergency_contact_id, patient_id, name, relationship, phone)
VALUES ('20000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001',
        'Synthetic Contact', 'Relative', '3000000000'),
       ('20000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000001',
        'Synthetic Contact', 'Relative', '3000000000');
SELECT pg_temp.expect_rejection($q$UPDATE patients.emergency_contact
    SET emergency_contact_id = '20000000-0000-4000-8000-000000000001'
    WHERE emergency_contact_id = '20000000-0000-4000-8000-000000000002'$q$,
    '23505', 'pk_emergency_contact');
SELECT pg_temp.expect_rejection($q$UPDATE patients.emergency_contact
    SET patient_id = '00000000-0000-4000-8000-000000000099'$q$,
    '23503', 'fk_emergency_contact_patient');
SELECT pg_temp.expect_rejection($q$INSERT INTO patients.emergency_contact
    VALUES ('20000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000099',
            'Orphan', 'Relative', '3000000000')$q$, '23503', 'fk_emergency_contact_patient');
SELECT pg_temp.expect_rejection($q$DELETE FROM patients.patient
    WHERE patient_id = '00000000-0000-4000-8000-000000000001'$q$,
    '23503', 'fk_emergency_contact_patient');
UPDATE patients.emergency_contact SET name = repeat('N', 255),
    relationship = repeat('R', 80), phone = repeat('1', 40);
UPDATE patients.patient SET status = 'INACTIVE'
WHERE patient_id = '00000000-0000-4000-8000-000000000001';
DO $$
DECLARE field text; sample record;
BEGIN
    IF (SELECT count(*) FROM patients.emergency_contact c JOIN patients.patient p
        USING (patient_id) WHERE p.status = 'INACTIVE') <> 2 OR
       EXISTS (SELECT FROM patients.emergency_contact
               WHERE patient_id = '00000000-0000-4000-8000-000000000002') THEN
        RAISE EXCEPTION 'Zero/multiple contacts or retention on deactivation failed';
    END IF;
    IF NOT EXISTS (SELECT FROM pg_index WHERE indrelid = 'patients.emergency_contact'::regclass
        AND indisvalid AND indkey[0] = (SELECT attnum FROM pg_attribute
            WHERE attrelid = 'patients.emergency_contact'::regclass AND attname = 'patient_id')) THEN
        RAISE EXCEPTION 'Patient reference lacks a usable leading-column index';
    END IF;
    FOREACH field IN ARRAY ARRAY['emergency_contact_id', 'patient_id', 'name', 'relationship', 'phone'] LOOP
        PERFORM pg_temp.expect_rejection(format('UPDATE patients.emergency_contact SET %I = NULL', field),
                                        '23502', field);
    END LOOP;
    FOR sample IN SELECT * FROM (VALUES
        ('name', $q$' '$q$, 'chk_emergency_contact_name'),
        ('name', $q$repeat('N', 256)$q$, 'chk_emergency_contact_name'),
        ('relationship', $q$E'\t\n'$q$, 'chk_emergency_contact_relationship'),
        ('relationship', $q$repeat('R', 81)$q$, 'chk_emergency_contact_relationship'),
        ('phone', $q$' '$q$, 'chk_emergency_contact_phone'),
        ('phone', $q$repeat('1', 41)$q$, 'chk_emergency_contact_phone')
    ) AS cases(field, expression, constraint_name) LOOP
        PERFORM pg_temp.expect_rejection(format('UPDATE patients.emergency_contact SET %I = %s',
            sample.field, sample.expression), '23514', sample.constraint_name);
    END LOOP;
END;
$$;
ROLLBACK;
