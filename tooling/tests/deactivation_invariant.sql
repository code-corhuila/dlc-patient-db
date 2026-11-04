SELECT pg_temp.register_patient(81, 'CC', 'INVARIANT-81');
INSERT INTO patients.deactivation_operation (operation_id,patient_id,actor_id,idempotency_key,expected_version,reason)
VALUES ('b8000000-0000-4000-8000-000000000081','00000000-0000-4000-8000-000000000081',
    '10000000-0000-4000-8000-000000000001','c8000000-0000-4000-8000-000000000081',1,'Administrative closure');
UPDATE patients.deactivation_operation SET guard_id='d8000000-0000-4000-8000-000000000081',guard_token_hash=repeat('a',64);
CREATE FUNCTION pg_temp.expect_at_commit(statements text[], expected text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE statement text; violated text;
BEGIN
    BEGIN
        FOREACH statement IN ARRAY statements LOOP EXECUTE statement; END LOOP;
        SET CONSTRAINTS ALL IMMEDIATE;
        RAISE EXCEPTION 'Expected % at commit', expected;
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS violated = CONSTRAINT_NAME;
        IF violated IS DISTINCT FROM expected THEN RAISE EXCEPTION 'Expected %, got %', expected, violated; END IF;
    END;
    SET CONSTRAINTS ALL DEFERRED;
END; $$;
CREATE TEMP TABLE proof_step (step text, statement text);
INSERT INTO proof_step VALUES
    ('profile', $q$UPDATE patients.patient SET status='INACTIVE',version=2 WHERE patient_id='00000000-0000-4000-8000-000000000081'$q$),
    ('audit', $q$INSERT INTO patients.patient_audit (audit_id,patient_id,actor_id,action,patient_version,reason) VALUES
        ('38000000-0000-4000-8000-000000000081','00000000-0000-4000-8000-000000000081',
         '10000000-0000-4000-8000-000000000001','DEACTIVATED',2,'Administrative closure')$q$),
    ('event', $q$INSERT INTO patients.outbox_event (event_id,aggregate_id,event_type,occurred_at,payload,correlation_id,causation_id)
        VALUES ('58000000-0000-4000-8000-000000000081','00000000-0000-4000-8000-000000000081','PatientDeactivated',statement_timestamp(),
        '{"patientId":"00000000-0000-4000-8000-000000000081","reasonCode":"ADMINISTRATIVE","deactivatedAt":"2026-01-01T00:00:00Z","deactivatedBy":"10000000-0000-4000-8000-000000000001"}',
        '68000000-0000-4000-8000-000000000081','78000000-0000-4000-8000-000000000081')$q$),
    ('operation', $q$UPDATE patients.deactivation_operation SET outcome='FINALIZED' WHERE operation_id='b8000000-0000-4000-8000-000000000081'$q$);
CREATE FUNCTION pg_temp.steps(names text[]) RETURNS text[] LANGUAGE sql AS $$
    SELECT array_agg(statement ORDER BY array_position(names, step)) FROM proof_step WHERE step = ANY(names) $$;
-- A status change alone, or without any one of its proofs, never commits.
SELECT pg_temp.expect_at_commit(pg_temp.steps('{profile}'), 'chk_patient_deactivation_proof');
SELECT pg_temp.expect_at_commit(pg_temp.steps('{profile,event,operation}'), 'chk_patient_deactivation_proof');
SELECT pg_temp.expect_at_commit(pg_temp.steps('{profile,audit,operation}'), 'chk_patient_deactivation_proof');
SELECT pg_temp.expect_at_commit(pg_temp.steps('{profile,audit,event}'), 'chk_patient_deactivation_proof');
-- A finalized operation without the deactivated profile never commits.
SELECT pg_temp.expect_at_commit(pg_temp.steps('{audit,event,operation}'), 'chk_deactivation_operation_proof');
DO $$ DECLARE statement text; BEGIN
    FOREACH statement IN ARRAY pg_temp.steps('{profile,audit,event,operation}') LOOP EXECUTE statement; END LOOP;
    SET CONSTRAINTS ALL IMMEDIATE;
    IF NOT EXISTS (SELECT FROM patients.patient WHERE patient_id='00000000-0000-4000-8000-000000000081'
        AND status='INACTIVE' AND version=2) THEN RAISE EXCEPTION 'Complete deactivation was rejected'; END IF;
END; $$;
ROLLBACK;
