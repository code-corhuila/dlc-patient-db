INSERT INTO patients.idempotency_record
    (actor_kind, actor_subject, operation, target_resource, idempotency_key, request_hash,
     response_status, response_body, response_location)
VALUES ('STAFF', '10000000-0000-4000-8000-000000000001', 'register', '/patients',
        '40000000-0000-4000-8000-000000000001', repeat('a', 64), 201,
        '{"id":"00000000-0000-4000-8000-000000000001"}', '/api/v1/patients/00000000-0000-4000-8000-000000000001');
CREATE FUNCTION pg_temp.retry_candidate(field text, value jsonb,
    target_key uuid DEFAULT '40000000-0000-4000-8000-000000000099') RETURNS void LANGUAGE sql AS $$
    INSERT INTO patients.idempotency_record SELECT (jsonb_populate_record(
        NULL::patients.idempotency_record, to_jsonb(r) ||
        jsonb_build_object('idempotency_key', target_key, 'expires_at', statement_timestamp() + INTERVAL '8 days') ||
        jsonb_build_object(field, value))).* FROM patients.idempotency_record r
    WHERE idempotency_key = '40000000-0000-4000-8000-000000000001'
      AND actor_kind = 'STAFF' AND actor_subject = '10000000-0000-4000-8000-000000000001'
      AND operation = 'register' AND target_resource = '/patients';
$$;
-- Both identical retries and changed payloads collide with the same durable scope.
SELECT pg_temp.expect_rejection($q$SELECT pg_temp.retry_candidate('idempotency_key',
    '"40000000-0000-4000-8000-000000000001"')$q$, '23505', 'pk_idempotency_record');
SELECT pg_temp.expect_rejection($q$SELECT pg_temp.retry_candidate('request_hash', to_jsonb(repeat('b',64)),
    '40000000-0000-4000-8000-000000000001')$q$, '23505', 'pk_idempotency_record');
SELECT pg_temp.expect_rejection($q$UPDATE patients.idempotency_record SET request_hash = repeat('b', 64)$q$,
                                '23514', 'ck_idempotency_records_immutable');
SELECT pg_temp.expect_rejection($q$UPDATE patients.idempotency_record SET response_body = '{"changed":true}'$q$,
                                '23514', 'ck_idempotency_records_immutable');
SELECT pg_temp.expect_rejection('UPDATE patients.idempotency_record SET expires_at = clock_timestamp()',
                                '23514', 'ck_idempotency_records_immutable');
SELECT pg_temp.expect_rejection('DELETE FROM patients.idempotency_record',
                                '23514', 'ck_idempotency_records_retention');
SELECT pg_temp.expect_rejection('TRUNCATE patients.idempotency_record',
                                '23514', 'ck_idempotency_records_immutable');
SELECT pg_temp.expect_rejection($q$INSERT INTO patients.idempotency_record
    (actor_kind,actor_subject,operation,target_resource,idempotency_key,request_hash,response_status,response_body)
    VALUES ('SERVICE','tests','register','/patients','40000000-0000-4000-8000-000000000099',
            repeat('a',64),201,'null'::jsonb)$q$, '23514', 'chk_idempotency_record_body');
-- The same key may be used by a different actor kind, subject, operation or resource.
INSERT INTO patients.idempotency_record SELECT (jsonb_populate_record(NULL::patients.idempotency_record,
    to_jsonb(r) || jsonb_build_object('expires_at', statement_timestamp() + INTERVAL '8 days') ||
    jsonb_build_object(s.field, s.value))).*
FROM patients.idempotency_record r CROSS JOIN (VALUES
    ('actor_kind', 'SERVICE'), ('actor_subject', 'other-service'),
    ('operation', 'deactivate'), ('target_resource', '/patients/other')) s(field, value);
DO $$
DECLARE field text; sample record;
BEGIN
    IF (SELECT count(*) FROM patients.idempotency_record) <> 5 OR EXISTS
        (SELECT FROM patients.idempotency_record WHERE expires_at < created_at + INTERVAL '7 days'
         OR response_status <> 201 OR response_body->>'id' <> '00000000-0000-4000-8000-000000000001') THEN
        RAISE EXCEPTION 'Scope separation, retention defaults or stored response failed';
    END IF;
    -- Scope this helper to the original record after creating independent scopes.
    FOR sample IN SELECT * FROM (VALUES
        ('actor_kind', '"UNKNOWN"', 'chk_idempotency_record_actor_kind'),
        ('actor_subject', '" "', 'chk_idempotency_record_actor_subject'),
        ('actor_subject', to_jsonb(repeat('a',256))::text, 'chk_idempotency_record_actor_subject'),
        ('operation', '" "', 'chk_idempotency_record_operation'),
        ('operation', to_jsonb(repeat('a',101))::text, 'chk_idempotency_record_operation'),
        ('target_resource', '" "', 'chk_idempotency_record_target'),
        ('target_resource', to_jsonb(repeat('a',256))::text, 'chk_idempotency_record_target'),
        ('request_hash', '"invalid"', 'chk_idempotency_record_hash'),
        ('response_status', '199', 'chk_idempotency_record_status'),
        ('response_status', '600', 'chk_idempotency_record_status'),
        ('response_body', '[]', 'chk_idempotency_record_body'),
        ('response_location', '"\r\nInjected: value"', 'chk_idempotency_record_location'),
        ('expires_at', '"2000-01-01T00:00:00Z"', 'chk_idempotency_record_retention')
    ) AS cases(field, value, constraint_name) LOOP
        PERFORM pg_temp.expect_rejection(format('SELECT pg_temp.retry_candidate(%L, %L::jsonb)',
            sample.field, sample.value), '23514', sample.constraint_name);
    END LOOP;
    FOREACH field IN ARRAY ARRAY['actor_kind','actor_subject','operation','target_resource',
        'idempotency_key','request_hash','response_status','response_body','expires_at'] LOOP
        PERFORM pg_temp.expect_rejection(format('SELECT pg_temp.retry_candidate(%L, NULL)', field),
                                        '23502', field);
    END LOOP;
END;
$$;
SAVEPOINT timestamp_check;
DO $$ DECLARE expected_stamp timestamptz := statement_timestamp();
BEGIN
    PERFORM pg_temp.retry_candidate('created_at', '"1900-01-01T00:00:00Z"');
    IF NOT EXISTS (SELECT FROM patients.idempotency_record WHERE
        idempotency_key='40000000-0000-4000-8000-000000000099' AND created_at=expected_stamp) THEN
        RAISE EXCEPTION 'Server did not replace the caller timestamp';
    END IF;
END; $$;
ROLLBACK TO timestamp_check;
SELECT pg_temp.register_patient(1, 'CC', 'RETRY-ATOMIC');
DO $$
DECLARE failed_constraint text;
BEGIN
    BEGIN
        UPDATE patients.patient SET name = 'Uncommitted retry';
        PERFORM pg_temp.retry_candidate('response_location', NULL);
        PERFORM pg_temp.retry_candidate('response_location', NULL);
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS failed_constraint = CONSTRAINT_NAME;
        IF failed_constraint <> 'pk_idempotency_record' THEN RAISE; END IF;
    END;
    IF EXISTS (SELECT FROM patients.patient WHERE name <> 'Synthetic Patient') OR
       EXISTS (SELECT FROM patients.idempotency_record WHERE
               idempotency_key = '40000000-0000-4000-8000-000000000099') THEN
        RAISE EXCEPTION 'Failed request retained a partial profile/journal write';
    END IF;
END; $$;
-- Privileged test setup ages one fixture; runtime must never have this privilege.
SET LOCAL session_replication_role = replica;
INSERT INTO patients.idempotency_record SELECT (jsonb_populate_record(NULL::patients.idempotency_record,
    to_jsonb(r) || jsonb_build_object('idempotency_key', '40000000-0000-4000-8000-000000000088',
        'created_at', statement_timestamp() - INTERVAL '192 hours',
        'expires_at', statement_timestamp() - INTERVAL '24 hours'))).*
FROM patients.idempotency_record r WHERE actor_kind = 'STAFF' AND
    actor_subject = '10000000-0000-4000-8000-000000000001' AND operation = 'register' AND target_resource = '/patients';
SET LOCAL session_replication_role = origin;
DELETE FROM patients.idempotency_record WHERE idempotency_key = '40000000-0000-4000-8000-000000000088';
DO $$ BEGIN
    IF (SELECT count(*) FROM patients.idempotency_record) <> 5 OR EXISTS (SELECT FROM
        patients.idempotency_record WHERE idempotency_key = '40000000-0000-4000-8000-000000000088') THEN
        RAISE EXCEPTION 'Expired cleanup removed retained results or failed to remove the expired fixture';
    END IF;
END; $$;
ROLLBACK;
