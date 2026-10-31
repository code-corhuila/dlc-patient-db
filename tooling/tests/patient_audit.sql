SELECT pg_temp.register_patient(1, 'CC', 'AUDIT-01');
INSERT INTO patients.patient_audit
    (audit_id, patient_id, actor_id, action, patient_version, changed_fields)
VALUES ('30000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001',
        '10000000-0000-4000-8000-000000000001', 'REGISTERED', 1, '{}');

CREATE FUNCTION pg_temp.audit_candidate(field text, value jsonb) RETURNS void
LANGUAGE sql AS $$
    INSERT INTO patients.patient_audit SELECT (jsonb_populate_record(NULL::patients.patient_audit,
        to_jsonb(a) || jsonb_build_object('audit_id', '30000000-0000-4000-8000-000000000099') ||
        jsonb_build_object(field, value))).*
    FROM patients.patient_audit a WHERE audit_id = '30000000-0000-4000-8000-000000000001';
$$;

SELECT pg_temp.expect_rejection($q$SELECT pg_temp.audit_candidate('audit_id',
    '"30000000-0000-4000-8000-000000000001"')$q$, '23505', 'pk_patient_audit');
SELECT pg_temp.expect_rejection($q$SELECT pg_temp.audit_candidate('patient_id',
    '"00000000-0000-4000-8000-000000000099"')$q$, '23503', 'fk_patient_audit_patient');
SELECT pg_temp.expect_rejection('DELETE FROM patients.patients', '23503', 'fk_patient_audit_patient');
SELECT pg_temp.expect_rejection('UPDATE patients.patient_audit SET patient_version = 2',
                                '23514', 'ck_patient_audit_append_only');
SELECT pg_temp.expect_rejection('DELETE FROM patients.patient_audit',
                                '23514', 'ck_patient_audit_append_only');
SELECT pg_temp.expect_rejection('TRUNCATE patients.patient_audit',
                                '23514', 'ck_patient_audit_append_only');
-- Either retained child may reject the cascade first; do not depend on trigger order.
DO $$ DECLARE blocked boolean := false; guard text;
BEGIN
    BEGIN
        TRUNCATE patients.patients CASCADE;
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS guard = CONSTRAINT_NAME;
        IF guard NOT IN ('ck_patient_audit_append_only','ck_outbox_events_immutable') THEN RAISE; END IF;
        blocked := true;
    END;
    IF NOT blocked THEN RAISE EXCEPTION 'Cascading truncation was accepted'; END IF;
END; $$;
DO $$
DECLARE field text; sample record;
BEGIN
    FOREACH field IN ARRAY ARRAY['audit_id', 'patient_id', 'actor_id', 'action',
                                 'patient_version', 'changed_fields'] LOOP
        PERFORM pg_temp.expect_rejection(format('SELECT pg_temp.audit_candidate(%L, NULL)', field),
                                        '23502', field);
    END LOOP;
    FOR sample IN SELECT * FROM (VALUES
        ('action', '"UNKNOWN"', 'ck_patient_audit_action'),
        ('patient_version', '0', 'ck_patient_audit_version'),
        ('changed_fields', '["diagnosis"]', 'ck_patient_audit_changed_fields'),
        ('changed_fields', '["documentNumber=123"]', 'ck_patient_audit_changed_fields'),
        ('changed_fields', '[null]', 'ck_patient_audit_changed_fields'),
        ('changed_fields', '[["name"]]', 'ck_patient_audit_changed_fields'),
        ('reason', '" "', 'ck_patient_audit_reason'),
        ('action', '"DEACTIVATED"', 'ck_patient_audit_deactivation_reason')
    ) AS cases(field, value, constraint_name) LOOP
        PERFORM pg_temp.expect_rejection(format('SELECT pg_temp.audit_candidate(%L, %L::jsonb)',
            sample.field, sample.value), '23514', sample.constraint_name);
    END LOOP;
END;
$$;
SELECT pg_temp.expect_rejection($q$SELECT pg_temp.audit_candidate('reason',
    to_jsonb(repeat('R', 1001)))$q$, '23514', 'ck_patient_audit_reason');
-- A rejected audit insert rolls back the profile change in the same local transaction.
DO $$
DECLARE rejected boolean := false; failure_constraint text;
BEGIN
    BEGIN
        UPDATE patients.patients SET name = 'Uncommitted profile', version = 2;
        PERFORM pg_temp.audit_candidate('actor_id', NULL);
    EXCEPTION WHEN not_null_violation THEN
        rejected := true;
    END;
    IF NOT rejected OR EXISTS (SELECT FROM patients.patients WHERE version <> 1
        OR name <> 'Synthetic Patient') OR (SELECT count(*) FROM patients.patient_audit) <> 1 THEN
        RAISE EXCEPTION 'Failed audit did not roll back its profile transaction';
    END IF;
    BEGIN
        UPDATE patients.patients SET name = 'Another uncommitted profile', version = 2;
        PERFORM pg_temp.audit_candidate('reason', '"Synthetic accepted reason"');
        -- Force a later failure after both writes; neither may survive.
        PERFORM pg_temp.audit_candidate('reason', '"Duplicate audit identity"');
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS failure_constraint = CONSTRAINT_NAME;
        IF failure_constraint <> 'pk_patient_audit' THEN RAISE; END IF;
    END;
    IF EXISTS (SELECT FROM patients.patients WHERE version <> 1 OR name <> 'Synthetic Patient')
        OR (SELECT count(*) FROM patients.patient_audit) <> 1 THEN
        RAISE EXCEPTION 'Later failure retained a partial profile/audit write';
    END IF;
END;
$$;
INSERT INTO patients.patient_audit
    (audit_id, patient_id, actor_id, action, patient_version, changed_fields, reason, recorded_at)
VALUES ('30000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000001',
        '10000000-0000-4000-8000-000000000001', 'PROFILE_UPDATED', 2,
        ARRAY['name', 'emergencyContacts'], NULL, NULL),
       ('30000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000001',
        '10000000-0000-4000-8000-000000000001', 'DEACTIVATED', 3,
        ARRAY['status'], repeat('R', 1000), '1900-01-01');
UPDATE patients.patients SET status = 'INACTIVE';
DO $$
BEGIN
    IF (SELECT count(*) FROM patients.patient_audit) <> 3 OR
       EXISTS (SELECT FROM patients.patient_audit WHERE recorded_at IS NULL OR
               recorded_at < CURRENT_TIMESTAMP OR recorded_at > clock_timestamp()) THEN
        RAISE EXCEPTION 'Audit retention or server timestamp failed';
    END IF;
    IF NOT EXISTS (SELECT FROM pg_index WHERE indrelid = 'patients.patient_audit'::regclass
        AND indisvalid AND indkey[0] = (SELECT attnum FROM pg_attribute
            WHERE attrelid = 'patients.patient_audit'::regclass AND attname = 'patient_id')) THEN
        RAISE EXCEPTION 'Patient audit reference lacks an index';
    END IF;
END;
$$;
ROLLBACK;
