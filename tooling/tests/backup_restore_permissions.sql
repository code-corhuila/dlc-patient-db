-- Authenticated runtime connection to the restored database; caller adds support.sql.
DO $$ DECLARE relation text; statement text;
BEGIN
    IF current_user<>'patients_runtime' OR session_user<>'patients_runtime' THEN
        RAISE EXCEPTION 'Recovery must verify an independently authenticated runtime';
    END IF;
    FOREACH relation IN ARRAY ARRAY['patients','emergency_contacts','patient_audit','idempotency_records',
        'outbox_events','inbox_events','deactivation_operations'] LOOP
        EXECUTE format('SELECT count(*) FROM patients.%I',relation);
    END LOOP;
    IF NOT EXISTS (SELECT FROM patients.deactivation_operations WHERE outcome='PENDING'
        AND guard_token_hash=repeat('b',64) AND completed_at IS NULL) THEN
        RAISE EXCEPTION 'Recovery resolved or lost the pending guarded operation';
    END IF;
    FOREACH statement IN ARRAY ARRAY['CREATE TABLE patients.forbidden(id integer)',
        'CREATE TABLE public.forbidden(id integer)','CREATE SCHEMA forbidden','SET ROLE postgres',
        'SELECT * FROM bootstrap_probe.marker','UPDATE bootstrap_probe.marker SET id=2',
        'SELECT * FROM public.databasechangelog_patients',
        'UPDATE public.databasechangeloglock_patients SET locked=false',
        'UPDATE patients.patient_audit SET reason=reason','DELETE FROM patients.deactivation_operations',
        'ALTER TABLE patients.patients DISABLE TRIGGER ALL'] LOOP
        BEGIN EXECUTE statement;
        EXCEPTION WHEN insufficient_privilege THEN CONTINUE;
        END;
        RAISE EXCEPTION 'Restored runtime unexpectedly allowed: %',statement;
    END LOOP;
END; $$;
SELECT pg_temp.expect_rejection($q$SELECT pg_temp.register_patient(100,' cc ',' recovery-99 ')$q$,
    '23505','uk_patients_document');
SELECT pg_temp.expect_rejection($q$INSERT INTO patients.idempotency_records
    (actor_kind,actor_subject,operation,target_resource,idempotency_key,request_hash,response_status,response_body)
    SELECT actor_kind,actor_subject,operation,target_resource,idempotency_key,request_hash,response_status,response_body
    FROM patients.idempotency_records$q$,
    '23505','pk_idempotency_records');
SELECT pg_temp.expect_rejection('INSERT INTO patients.outbox_events SELECT * FROM patients.outbox_events',
    '23505','pk_outbox_events');
SELECT pg_temp.expect_rejection('INSERT INTO patients.inbox_events SELECT * FROM patients.inbox_events',
    '23505','pk_inbox_events');
SELECT pg_temp.expect_rejection($q$INSERT INTO patients.emergency_contacts VALUES (
    '20000000-0000-4000-8000-000000000100','00000000-0000-4000-8000-000000000100',
    'Synthetic Orphan','Relative','3000000000')$q$,'23503','fk_emergency_contacts_patient');
UPDATE patients.patients SET name='Restored Synthetic',version=version+1,updated_at=statement_timestamp();
ROLLBACK;
