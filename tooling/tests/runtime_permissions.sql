DO $$ BEGIN
    IF current_user<>'patients_runtime' OR session_user<>'patients_runtime' THEN
        RAISE EXCEPTION 'Runtime must authenticate independently of the migrator';
    END IF;
END; $$;
CREATE FUNCTION pg_temp.expect_denied(statement text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    BEGIN EXECUTE statement;
    EXCEPTION WHEN insufficient_privilege THEN RETURN;
    END;
    RAISE EXCEPTION 'Expected SQLSTATE 42501 for %',statement;
END; $$;
SELECT pg_temp.register_patient(71,'CC','RUNTIME-71');
UPDATE patients.patient SET name='Runtime Synthetic',version=2,updated_at=statement_timestamp();
INSERT INTO patients.emergency_contact VALUES ('20000000-0000-4000-8000-000000000071',
    '00000000-0000-4000-8000-000000000071','Synthetic Contact','Relative','3000000000');
UPDATE patients.emergency_contact SET phone='3000000001';
DELETE FROM patients.emergency_contact;
INSERT INTO patients.patient_audit (audit_id,patient_id,actor_id,action,patient_version,changed_fields)
VALUES ('30000000-0000-4000-8000-000000000071','00000000-0000-4000-8000-000000000071',
    '10000000-0000-4000-8000-000000000001','PROFILE_UPDATED',2,ARRAY['name']);
INSERT INTO patients.idempotency_record (actor_kind,actor_subject,operation,target_resource,
    idempotency_key,request_hash,response_status,response_body) VALUES
    ('SERVICE','runtime-test','register','/patients','40000000-0000-4000-8000-000000000071',repeat('a',64),201,'{}');
SELECT pg_temp.expect_rejection('DELETE FROM patients.idempotency_record','23514','chk_idempotency_record_retention');
INSERT INTO patients.outbox_event (event_id,aggregate_id,event_type,occurred_at,payload,correlation_id,causation_id)
VALUES ('50000000-0000-4000-8000-000000000071','00000000-0000-4000-8000-000000000071',
    'PatientProfileUpdated',statement_timestamp(),'{"patientId":"00000000-0000-4000-8000-000000000071",
    "changedFields":["name"],"updatedAt":"2026-01-01T00:00:00Z","updatedBy":"10000000-0000-4000-8000-000000000001"}',
    '60000000-0000-4000-8000-000000000001','70000000-0000-4000-8000-000000000001');
SELECT event_id FROM patients.outbox_event FOR UPDATE SKIP LOCKED;
UPDATE patients.outbox_event SET status='PUBLISHED',attempts=1,next_retry_at=NULL;
SELECT pg_temp.receive_assignment('80000000-0000-4000-8000-000000000071');
SELECT event_id FROM patients.inbox_event FOR UPDATE SKIP LOCKED;
UPDATE patients.inbox_event SET status='PROCESSED',attempts=1,next_retry_at=NULL;
DO $$ DECLARE statement text; relation text;
BEGIN
    FOREACH relation IN ARRAY ARRAY(SELECT c.relname::text FROM pg_class c WHERE c.relnamespace='patients'::regnamespace
        AND c.relkind='r' AND c.relname NOT LIKE 'deactivation_operation%' AND c.relname<>'runtime_future_probe') LOOP
        EXECUTE format('SELECT count(*) FROM patients.%I',relation);
        PERFORM pg_temp.expect_denied(format('TRUNCATE patients.%I',relation));
        PERFORM pg_temp.expect_denied(format('ALTER TABLE patients.%I ADD COLUMN forbidden integer',relation));
    END LOOP;
    FOREACH statement IN ARRAY ARRAY[
        'DELETE FROM patients.patient', 'DELETE FROM patients.patient_audit',
        'UPDATE patients.patient_audit SET reason=reason', 'UPDATE patients.idempotency_record SET request_hash=request_hash',
        'DELETE FROM patients.outbox_event', 'DELETE FROM patients.inbox_event',
        'UPDATE patients.outbox_event SET payload=payload', 'UPDATE patients.inbox_event SET assignment_version=assignment_version',
        'UPDATE patients.patient SET created_by=created_by', 'UPDATE patients.emergency_contact SET patient_id=patient_id',
        'CREATE TABLE patients.forbidden(id integer)', 'CREATE TABLE public.forbidden(id integer)',
        'CREATE SCHEMA forbidden', 'CREATE ROLE forbidden', 'SET ROLE postgres',
        'SELECT * FROM bootstrap_probe.marker', 'INSERT INTO bootstrap_probe.marker VALUES (2)',
        'UPDATE bootstrap_probe.marker SET id=2', 'DELETE FROM bootstrap_probe.marker',
        'SELECT * FROM public.databasechangelog_patients', 'DELETE FROM public.databasechangelog_patients',
        'UPDATE public.databasechangeloglock_patients SET locked=false',
        'ALTER TABLE patients.patient DISABLE TRIGGER ALL',
        'UPDATE patients.outbox_event SET published_at=published_at',
        'UPDATE patients.inbox_event SET processed_at=processed_at',
        'SELECT * FROM patients.runtime_future_probe', 'INSERT INTO patients.runtime_future_probe VALUES (1)',
        'UPDATE patients.runtime_future_probe SET id=2', 'DELETE FROM patients.runtime_future_probe'
    ] LOOP PERFORM pg_temp.expect_denied(statement); END LOOP;
    EXECUTE 'GRANT SELECT ON patients.patient TO PUBLIC';
    IF EXISTS (SELECT FROM pg_class c, LATERAL aclexplode(c.relacl) a
        WHERE c.oid='patients.patient'::regclass AND a.grantee=0 AND a.privilege_type='SELECT') THEN
        RAISE EXCEPTION 'Runtime re-granted patient access';
    END IF;
    IF NOT EXISTS (SELECT FROM patients.outbox_event WHERE published_at IS NOT NULL) OR
       NOT EXISTS (SELECT FROM patients.inbox_event WHERE processed_at IS NOT NULL) THEN
        RAISE EXCEPTION 'Invoker triggers did not stamp worker outcomes';
    END IF;
END; $$;
DO $$ BEGIN
    IF to_regclass('patients.deactivation_operation') IS NOT NULL THEN
        INSERT INTO patients.deactivation_operation (operation_id,patient_id,actor_id,idempotency_key,expected_version,reason)
        VALUES ('b1000000-0000-4000-8000-000000000071','00000000-0000-4000-8000-000000000071',
            '10000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000071',2,'Synthetic intent');
        UPDATE patients.deactivation_operation SET guard_id='d1000000-0000-4000-8000-000000000071',guard_token_hash=repeat('a',64);
        UPDATE patients.deactivation_operation SET outcome='ABORTED';
        PERFORM operation_id FROM patients.deactivation_operation FOR UPDATE SKIP LOCKED;
        PERFORM pg_temp.expect_denied('UPDATE patients.deactivation_operation SET reason=reason');
        PERFORM pg_temp.expect_denied('DELETE FROM patients.deactivation_operation');
        PERFORM pg_temp.expect_denied('TRUNCATE patients.deactivation_operation');
    END IF;
END; $$;
ROLLBACK;
