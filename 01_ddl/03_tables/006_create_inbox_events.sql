CREATE TABLE patients.inbox_events (
    event_id uuid CONSTRAINT pk_inbox_events PRIMARY KEY,
    aggregate_id uuid NOT NULL,
    event_type text NOT NULL,
    aggregate_type text NOT NULL DEFAULT 'ClinicalAssignment',
    event_version integer NOT NULL DEFAULT 1,
    producer text NOT NULL DEFAULT 'appointments-service',
    assignment_version integer NOT NULL,
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT statement_timestamp(),
    payload jsonb NOT NULL,
    correlation_id uuid NOT NULL,
    causation_id uuid NOT NULL,
    actor_user_id uuid,
    status text NOT NULL DEFAULT 'PENDING',
    attempts integer NOT NULL DEFAULT 0,
    next_retry_at timestamptz DEFAULT statement_timestamp(),
    processed_at timestamptz,
    error_code text,
    CONSTRAINT ck_inbox_events_type CHECK (event_type IN ('ClinicalAssignmentStarted','ClinicalAssignmentEnded')),
    CONSTRAINT ck_inbox_events_aggregate_type CHECK (aggregate_type='ClinicalAssignment'),
    CONSTRAINT ck_inbox_events_version CHECK (event_version=1),
    CONSTRAINT ck_inbox_events_producer CHECK (producer='appointments-service'),
    CONSTRAINT ck_inbox_events_assignment_version CHECK (assignment_version>0),
    CONSTRAINT ck_inbox_events_time CHECK (isfinite(occurred_at)),
    CONSTRAINT ck_inbox_events_payload CHECK (CASE WHEN jsonb_typeof(payload) IS DISTINCT FROM 'object'
        THEN false ELSE coalesce(lower(payload->>'assignmentId')=aggregate_id::text,false)
        AND coalesce(payload->'version'=to_jsonb(assignment_version),false) AND CASE event_type
        WHEN 'ClinicalAssignmentStarted' THEN
            jsonb_exists_all(payload,ARRAY['assignmentId','patientId','dentistId','startedAt','startedBy','version'])
            AND payload - ARRAY['assignmentId','patientId','dentistId','startedAt','startedBy','version']='{}'::jsonb
        WHEN 'ClinicalAssignmentEnded' THEN
            jsonb_exists_all(payload,ARRAY['assignmentId','patientId','dentistId','endedAt','endedBy','version'])
            AND payload - ARRAY['assignmentId','patientId','dentistId','endedAt','endedBy','version']='{}'::jsonb
        ELSE true END END),
    CONSTRAINT ck_inbox_events_error CHECK (error_code IS NULL OR error_code ~ '^[A-Z][A-Z0-9_]{0,99}$'),
    CONSTRAINT ck_inbox_events_delivery CHECK (attempts>=0 AND (
        (status='PENDING' AND next_retry_at IS NOT NULL AND isfinite(next_retry_at) AND processed_at IS NULL) OR
        (status='PROCESSED' AND attempts>0 AND next_retry_at IS NULL AND error_code IS NULL
            AND processed_at IS NOT NULL AND isfinite(processed_at)) OR
        (status='FAILED' AND attempts>0 AND next_retry_at IS NULL AND processed_at IS NULL AND error_code IS NOT NULL)))
);
