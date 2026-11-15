SELECT pg_temp.receive_assignment('80000000-0000-4000-8000-000000000001');
CREATE FUNCTION pg_temp.inbox_candidate(changes jsonb) RETURNS void LANGUAGE sql AS $$
    INSERT INTO patients.inbox_event SELECT (jsonb_populate_record(NULL::patients.inbox_event,
        to_jsonb(e) || jsonb_build_object('event_id','80000000-0000-4000-8000-000000000099') || changes)).*
    FROM patients.inbox_event e WHERE event_id='80000000-0000-4000-8000-000000000001';
$$;
SELECT pg_temp.expect_rejection($q$SELECT pg_temp.inbox_candidate('{}')$q$,'23505','uk_inbox_event_source');
SELECT pg_temp.expect_rejection($q$SELECT pg_temp.inbox_candidate('{"event_id":"80000000-0000-4000-8000-000000000001",
    "assignment_version":2,"payload":{"assignmentId":"90000000-0000-4000-8000-000000000001",
    "patientId":"00000000-0000-4000-8000-000000000099","dentistId":"10000000-0000-4000-8000-000000000001",
    "startedAt":"2026-01-01T00:00:00Z","startedBy":"10000000-0000-4000-8000-000000000001","version":2}}')$q$,
    '23505','pk_inbox_event');
DO $$ DECLARE field text; sample record;
BEGIN
    FOREACH field IN ARRAY ARRAY['event_id','aggregate_id','event_type','aggregate_type','event_version',
        'producer','occurred_at','assignment_version','payload','correlation_id','causation_id','status','attempts'] LOOP
        PERFORM pg_temp.expect_rejection(format('SELECT pg_temp.inbox_candidate(jsonb_build_object(%L,NULL))',field),'23502',field);
    END LOOP;
    FOR sample IN SELECT * FROM (VALUES
        ('event_type','"Unknown"','chk_inbox_event_type'),
        ('event_version','2','chk_inbox_event_version'),
        ('aggregate_type','"Patient"','chk_inbox_event_aggregate_type'),
        ('producer','"clinical-service"','chk_inbox_event_producer'),
        ('payload','{}','chk_inbox_event_payload'),
        ('payload','[]','chk_inbox_event_payload'),
        ('assignment_version','0','chk_inbox_event_assignment_version'),
        ('status','"PROCESSED"','chk_inbox_event_initial'),
        ('attempts','-1','chk_inbox_event_initial'),
        ('next_retry_at','null','chk_inbox_event_delivery')
    ) AS cases(field,value,constraint_name) LOOP
        PERFORM pg_temp.expect_rejection(format('SELECT pg_temp.inbox_candidate(jsonb_build_object(%L,%L::jsonb))',
            sample.field,sample.value),'23514',sample.constraint_name);
    END LOOP;
END; $$;
SELECT pg_temp.expect_rejection($q$SELECT pg_temp.inbox_candidate(jsonb_build_object('payload',
    (SELECT payload || '{"clinicalHistory":"forbidden"}' FROM patients.inbox_event)))$q$,'23514','chk_inbox_event_payload');
SELECT pg_temp.expect_rejection($q$SELECT pg_temp.inbox_candidate('{"assignment_version":2}')$q$,'23514','chk_inbox_event_payload');
SELECT pg_temp.expect_rejection('DELETE FROM patients.inbox_event','23514','chk_inbox_event_immutable');
SELECT pg_temp.expect_rejection('TRUNCATE patients.inbox_event','23514','chk_inbox_event_immutable');
SELECT pg_temp.expect_rejection($q$UPDATE patients.inbox_event SET payload='{}'$q$,'23514','chk_inbox_event_immutable');
-- A synthetic local effect and its inbox marker must roll back together.
CREATE TEMP TABLE consumer_effects (event_id uuid PRIMARY KEY);
DO $$ DECLARE rejected text;
BEGIN
    BEGIN
        INSERT INTO consumer_effects SELECT event_id FROM patients.inbox_event;
        UPDATE patients.inbox_event SET status='PROCESSED',attempts=1,next_retry_at=NULL;
        PERFORM pg_temp.inbox_candidate('{"event_type":"Unknown","status":"PENDING","attempts":0,"processed_at":null,"next_retry_at":"2026-01-01T00:00:00Z"}');
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS rejected=CONSTRAINT_NAME;
        IF rejected<>'chk_inbox_event_type' THEN RAISE; END IF;
    END;
    IF EXISTS (SELECT FROM consumer_effects) OR EXISTS (SELECT FROM patients.inbox_event WHERE status<>'PENDING') THEN
        RAISE EXCEPTION 'Partial inbox/effect write survived';
    END IF;
END; $$;
-- Both assignment events are accepted without a cross-owner or local patient FK.
SELECT pg_temp.inbox_candidate('{"event_type":"ClinicalAssignmentEnded","assignment_version":2,"payload":{
    "assignmentId":"90000000-0000-4000-8000-000000000001","patientId":"00000000-0000-4000-8000-000000000099",
    "dentistId":"10000000-0000-4000-8000-000000000001","endedAt":"2026-01-01T00:01:00Z",
    "endedBy":"10000000-0000-4000-8000-000000000001","version":2}}');
UPDATE patients.inbox_event SET status='FAILED',attempts=1,next_retry_at=NULL,error_code='CACHE_UNAVAILABLE';
UPDATE patients.inbox_event SET status='PENDING',attempts=2,next_retry_at=statement_timestamp(),error_code=NULL;
SELECT pg_temp.expect_rejection('UPDATE patients.inbox_event SET attempts=1','23514','chk_inbox_event_delivery');
INSERT INTO consumer_effects SELECT event_id FROM patients.inbox_event;
UPDATE patients.inbox_event SET status='PROCESSED',attempts=3,next_retry_at=NULL;
SELECT pg_temp.expect_rejection($q$UPDATE patients.inbox_event SET status='PENDING',
    next_retry_at=statement_timestamp(),processed_at=NULL$q$,'23514','chk_inbox_event_delivery');
DO $$ BEGIN
    IF (SELECT count(*) FROM consumer_effects)<>2 OR
       (SELECT count(*) FROM patients.inbox_event WHERE status='PROCESSED' AND processed_at>=CURRENT_TIMESTAMP)<>2 THEN
        RAISE EXCEPTION 'Missing committed local effect or processing marker';
    END IF;
END; $$;
ROLLBACK;
