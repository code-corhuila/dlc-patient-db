SELECT pg_temp.register_patient(1,'CC','DEACT-01');
INSERT INTO patients.deactivation_operations (operation_id,patient_id,actor_id,idempotency_key,expected_version,reason)
VALUES ('b1000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001',1,'Administrative closure');
CREATE FUNCTION pg_temp.operation_candidate(changes jsonb) RETURNS void LANGUAGE sql AS $$
    INSERT INTO patients.deactivation_operations SELECT (jsonb_populate_record(NULL::patients.deactivation_operations,
        to_jsonb(o)||'{"operation_id":"b1000000-0000-4000-8000-000000000099","idempotency_key":"c1000000-0000-4000-8000-000000000099"}'||changes)).*
    FROM patients.deactivation_operations o WHERE operation_id='b1000000-0000-4000-8000-000000000001';
$$;
SELECT pg_temp.expect_rejection($q$SELECT pg_temp.operation_candidate('{"operation_id":"b1000000-0000-4000-8000-000000000001"}')$q$,'23505','pk_deactivation_operations');
SELECT pg_temp.expect_rejection($q$SELECT pg_temp.operation_candidate('{"idempotency_key":"c1000000-0000-4000-8000-000000000001"}')$q$,'23505','uk_deactivation_operations_request');
SELECT pg_temp.expect_rejection($q$SELECT pg_temp.operation_candidate('{"patient_id":"00000000-0000-4000-8000-000000000099"}')$q$,'23503','fk_deactivation_operations_patient');
DO $$ DECLARE field text; sample record;
BEGIN
    FOREACH field IN ARRAY ARRAY['operation_id','patient_id','actor_id','idempotency_key','expected_version','reason','outcome'] LOOP
        PERFORM pg_temp.expect_rejection(format('SELECT pg_temp.operation_candidate(jsonb_build_object(%L,NULL))',field),'23502',field);
    END LOOP;
    FOR sample IN SELECT * FROM (VALUES
        ('{"expected_version":0}','ck_deactivation_operations_version'),
        ('{"reason":" "}','ck_deactivation_operations_reason'),
        ('{"outcome":"ABORTED"}','ck_deactivation_operations_initial'),
        ('{"guard_token_hash":"raw-proof"}','ck_deactivation_operations_initial')
    ) s(value,expected) LOOP
        PERFORM pg_temp.expect_rejection(format('SELECT pg_temp.operation_candidate(%L)',sample.value),'23514',sample.expected);
    END LOOP;
END; $$;
-- Same key for another actor is a separate request; no global per-patient pending restriction.
SELECT pg_temp.operation_candidate('{"actor_id":"10000000-0000-4000-8000-000000000002","idempotency_key":"c1000000-0000-4000-8000-000000000001"}');
SELECT pg_temp.expect_rejection('DELETE FROM patients.patients','23503','fk_deactivation_operations_patient');
SELECT pg_temp.expect_rejection('DELETE FROM patients.deactivation_operations','23514','ck_deactivation_operations_immutable');
SELECT pg_temp.expect_rejection('TRUNCATE patients.deactivation_operations','23514','ck_deactivation_operations_immutable');
SELECT pg_temp.expect_rejection($q$UPDATE patients.deactivation_operations SET reason='Changed'$q$,'23514','ck_deactivation_operations_immutable');
SELECT pg_temp.expect_rejection($q$UPDATE patients.deactivation_operations SET guard_id='d1000000-0000-4000-8000-000000000001'$q$,'23514','ck_deactivation_operations_guard');
UPDATE patients.deactivation_operations SET guard_id='d1000000-0000-4000-8000-000000000001',guard_token_hash=repeat('a',64)
WHERE actor_id='10000000-0000-4000-8000-000000000001';
SELECT pg_temp.expect_rejection($q$UPDATE patients.deactivation_operations SET guard_id='d1000000-0000-4000-8000-000000000001',guard_token_hash=repeat('b',64)
    WHERE actor_id='10000000-0000-4000-8000-000000000002'$q$,'23505','uk_deactivation_operations_guard');
SELECT pg_temp.expect_rejection($q$UPDATE patients.deactivation_operations SET guard_token_hash='raw-proof'$q$,'23514','ck_deactivation_operations_guard');
SELECT pg_temp.expect_rejection($q$UPDATE patients.deactivation_operations SET outcome='FINALIZED' WHERE guard_id IS NULL$q$,'23514','ck_deactivation_operations_outcome');
UPDATE patients.deactivation_operations SET guard_token_hash=repeat('b',64) WHERE guard_id IS NOT NULL;
CREATE FUNCTION pg_temp.finish_deactivation() RETURNS void LANGUAGE plpgsql AS $$ BEGIN
    UPDATE patients.patients SET status='INACTIVE',version=2;
    INSERT INTO patients.patient_audit (audit_id,patient_id,actor_id,action,patient_version,reason)
    VALUES ('30000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001',
        '10000000-0000-4000-8000-000000000001','DEACTIVATED',2,'Administrative closure');
    INSERT INTO patients.outbox_events (event_id,aggregate_id,event_type,occurred_at,payload,correlation_id,causation_id)
    VALUES ('50000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','PatientDeactivated',statement_timestamp(),
        '{"patientId":"00000000-0000-4000-8000-000000000001","reasonCode":"ADMINISTRATIVE","deactivatedAt":"2026-01-01T00:00:00Z","deactivatedBy":"10000000-0000-4000-8000-000000000001"}',
        '60000000-0000-4000-8000-000000000001','70000000-0000-4000-8000-000000000001');
    UPDATE patients.deactivation_operations SET outcome='FINALIZED' WHERE guard_id IS NOT NULL;
END; $$;
DO $$ BEGIN
    BEGIN PERFORM pg_temp.finish_deactivation(); PERFORM 1/0;
    EXCEPTION WHEN division_by_zero THEN NULL; END;
    IF EXISTS (SELECT FROM patients.patients WHERE status<>'ACTIVE') OR EXISTS (SELECT FROM patients.patient_audit) OR
       EXISTS (SELECT FROM patients.outbox_events) OR EXISTS (SELECT FROM patients.deactivation_operations WHERE outcome<>'PENDING') THEN
        RAISE EXCEPTION 'Partial deactivation survived rollback';
    END IF;
END; $$;
SELECT pg_temp.finish_deactivation();
UPDATE patients.deactivation_operations SET outcome='ABORTED' WHERE guard_id IS NULL;
SELECT pg_temp.expect_rejection($q$UPDATE patients.deactivation_operations SET outcome='PENDING'$q$,'23514','ck_deactivation_operations_transition');
SELECT pg_temp.expect_rejection($q$UPDATE patients.deactivation_operations SET outcome='ABORTED' WHERE outcome='FINALIZED'$q$,'23514','ck_deactivation_operations_transition');
SELECT pg_temp.expect_rejection($q$UPDATE patients.deactivation_operations SET guard_id='d1000000-0000-4000-8000-000000000002' WHERE guard_id IS NOT NULL$q$,'23514','ck_deactivation_operations_immutable');
DO $$ DECLARE original_completion timestamptz; BEGIN
    SELECT completed_at INTO original_completion FROM patients.deactivation_operations WHERE guard_id IS NOT NULL;
    UPDATE patients.deactivation_operations SET guard_token_hash=repeat('c',64) WHERE guard_id IS NOT NULL;
    IF NOT EXISTS (SELECT FROM patients.deactivation_operations WHERE outcome='FINALIZED' AND operation_version=5
        AND completed_at=original_completion AND guard_token_hash=repeat('c',64))
        OR NOT EXISTS (SELECT FROM patients.patients WHERE status='INACTIVE' AND version=2) OR (SELECT count(*) FROM patients.patient_audit)<>1 OR
        (SELECT count(*) FROM patients.outbox_events)<>1 THEN RAISE EXCEPTION 'Terminal fact or rotated proof lost'; END IF;
END; $$;
ROLLBACK;
