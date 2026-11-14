SELECT pg_temp.register_patient(1, 'CC', 'OUTBOX-01');
INSERT INTO patients.outbox_event (event_id, aggregate_id, event_type, occurred_at, payload,
                                   correlation_id, causation_id)
VALUES ('50000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001',
    'PatientRegistered', '2026-01-01T00:00:00Z', '{"patientId":"00000000-0000-4000-8000-000000000001",
    "status":"ACTIVE","registeredAt":"2026-01-01T00:00:00Z","registeredBy":"10000000-0000-4000-8000-000000000001"}',
    '60000000-0000-4000-8000-000000000001','70000000-0000-4000-8000-000000000001');
CREATE FUNCTION pg_temp.outbox_candidate(field text, value jsonb) RETURNS void LANGUAGE sql AS $$
    INSERT INTO patients.outbox_event SELECT (jsonb_populate_record(NULL::patients.outbox_event,
        to_jsonb(e) || jsonb_build_object('event_id','50000000-0000-4000-8000-000000000099') ||
        jsonb_build_object(field,value))).* FROM patients.outbox_event e
    WHERE event_id = '50000000-0000-4000-8000-000000000001';
$$;
SELECT pg_temp.expect_rejection($q$SELECT pg_temp.outbox_candidate('event_id',
    '"50000000-0000-4000-8000-000000000001"')$q$, '23505', 'pk_outbox_event');
SELECT pg_temp.expect_rejection($q$SELECT pg_temp.outbox_candidate('aggregate_id',
    '"00000000-0000-4000-8000-000000000099"')$q$, '23514', 'chk_outbox_event_payload');
SELECT pg_temp.expect_rejection('DELETE FROM patients.patient', '23503', 'fk_outbox_event_patient');
SELECT pg_temp.expect_rejection($q$INSERT INTO patients.outbox_event SELECT (jsonb_populate_record(NULL::patients.outbox_event,
    to_jsonb(e) || jsonb_build_object('event_id','50000000-0000-4000-8000-000000000099',
    'aggregate_id','00000000-0000-4000-8000-000000000099','payload',jsonb_set(e.payload,'{patientId}',
    '"00000000-0000-4000-8000-000000000099"')))).* FROM patients.outbox_event e$q$,
    '23503','fk_outbox_event_patient');
SELECT pg_temp.expect_rejection('DELETE FROM patients.outbox_event', '23514', 'chk_outbox_event_immutable');
SELECT pg_temp.expect_rejection('TRUNCATE patients.outbox_event', '23514', 'chk_outbox_event_immutable');
SELECT pg_temp.expect_rejection($q$UPDATE patients.outbox_event SET payload = '{}'$q$,
                                '23514','chk_outbox_event_immutable');
DO $$
DECLARE field text; sample record;
BEGIN
    FOREACH field IN ARRAY ARRAY['event_id','aggregate_id','event_type','aggregate_type','event_version',
        'producer','occurred_at','payload','correlation_id','causation_id','status','attempts'] LOOP
        PERFORM pg_temp.expect_rejection(format('SELECT pg_temp.outbox_candidate(%L,NULL)',field),'23502',field);
    END LOOP;
    FOR sample IN SELECT * FROM (VALUES
        ('event_type','"Unknown"','chk_outbox_event_type'),
        ('event_version','2','chk_outbox_event_version'),
        ('aggregate_type','"ClinicalRecord"','chk_outbox_event_aggregate_type'),
        ('producer','"clinical-service"','chk_outbox_event_producer'),
        ('payload','{}','chk_outbox_event_payload'),
        ('payload','[]','chk_outbox_event_payload'),
        ('status','"PUBLISHED"','chk_outbox_event_initial'),
        ('next_retry_at','null','chk_outbox_event_delivery'),
        ('attempts','-1','chk_outbox_event_initial')
    ) AS cases(field,value,constraint_name) LOOP
        PERFORM pg_temp.expect_rejection(format('SELECT pg_temp.outbox_candidate(%L,%L::jsonb)',
            sample.field,sample.value),'23514',sample.constraint_name);
    END LOOP;
END; $$;
INSERT INTO patients.outbox_event SELECT (jsonb_populate_record(NULL::patients.outbox_event,
    to_jsonb(e) || jsonb_build_object('event_id',s.id,'event_type',s.kind,'payload',s.body::jsonb))).*
FROM patients.outbox_event e CROSS JOIN (VALUES
    ('50000000-0000-4000-8000-000000000002','PatientProfileUpdated',
     '{"patientId":"00000000-0000-4000-8000-000000000001","changedFields":["name"],"updatedAt":"2026-01-01T00:00:00Z","updatedBy":"10000000-0000-4000-8000-000000000001"}'),
    ('50000000-0000-4000-8000-000000000003','PatientDeactivated',
     '{"patientId":"00000000-0000-4000-8000-000000000001","reasonCode":"ADMINISTRATIVE","deactivatedAt":"2026-01-01T00:00:00Z","deactivatedBy":"10000000-0000-4000-8000-000000000001"}')
) s(id,kind,body);
SELECT pg_temp.expect_rejection($q$SELECT pg_temp.outbox_candidate('payload',
    (SELECT payload || '{"clinicalHistory":"forbidden"}' FROM patients.outbox_event LIMIT 1))$q$,
    '23514','chk_outbox_event_payload');
-- Failing the outbox insert must roll back the accompanying local profile change.
DO $$ DECLARE failed_constraint text; initial_count integer;
BEGIN
    SELECT count(*) INTO initial_count FROM patients.outbox_event;
    BEGIN
        UPDATE patients.patient SET name = 'Uncommitted event';
        PERFORM pg_temp.outbox_candidate('event_type','"Unknown"');
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'chk_outbox_event_type' THEN RAISE; END IF;
    END;
    IF EXISTS (SELECT FROM patients.patient WHERE name <> 'Synthetic Patient') OR
       (SELECT count(*) FROM patients.outbox_event) <> initial_count THEN
        RAISE EXCEPTION 'Partial profile/outbox write survived';
    END IF;
END; $$;
UPDATE patients.outbox_event SET status='FAILED',attempts=1,next_retry_at=NULL,error_code='BROKER_UNAVAILABLE';
UPDATE patients.outbox_event SET status='PENDING',attempts=2,next_retry_at=statement_timestamp();
SELECT pg_temp.expect_rejection('UPDATE patients.outbox_event SET attempts=1',
                                '23514','chk_outbox_event_delivery');
UPDATE patients.outbox_event SET status='PUBLISHED',attempts=3,next_retry_at=NULL,error_code=NULL;
SELECT pg_temp.expect_rejection($q$UPDATE patients.outbox_event SET status='PENDING',
    next_retry_at=statement_timestamp(),published_at=NULL$q$,'23514','chk_outbox_event_delivery');
DO $$ BEGIN
    IF (SELECT count(*) FROM patients.outbox_event)<>3 OR NOT EXISTS (SELECT FROM patients.outbox_event WHERE status='PUBLISHED' AND attempts=3
        AND published_at >= CURRENT_TIMESTAMP AND payload->>'status'='ACTIVE') THEN
        RAISE EXCEPTION 'Publication marker or original payload changed';
    END IF;
END; $$;
ROLLBACK;
