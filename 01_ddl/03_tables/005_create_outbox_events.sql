CREATE TABLE patients.outbox_events (
    event_id uuid CONSTRAINT pk_outbox_events PRIMARY KEY,
    aggregate_id uuid NOT NULL,
    event_type text NOT NULL,
    aggregate_type text NOT NULL DEFAULT 'Patient',
    event_version integer NOT NULL DEFAULT 1,
    producer text NOT NULL DEFAULT 'patients-service',
    occurred_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT statement_timestamp(),
    payload jsonb NOT NULL,
    correlation_id uuid NOT NULL,
    causation_id uuid NOT NULL,
    actor_user_id uuid,
    status text NOT NULL DEFAULT 'PENDING',
    attempts integer NOT NULL DEFAULT 0,
    next_retry_at timestamptz DEFAULT statement_timestamp(),
    published_at timestamptz,
    error_code text,
    CONSTRAINT ck_outbox_events_type CHECK
        (event_type IN ('PatientRegistered','PatientProfileUpdated','PatientDeactivated')),
    CONSTRAINT ck_outbox_events_aggregate_type CHECK (aggregate_type='Patient'),
    CONSTRAINT ck_outbox_events_version CHECK (event_version=1),
    CONSTRAINT ck_outbox_events_producer CHECK (producer='patients-service'),
    CONSTRAINT ck_outbox_events_time CHECK (isfinite(occurred_at)),
    CONSTRAINT ck_outbox_events_payload CHECK (CASE WHEN jsonb_typeof(payload) IS DISTINCT FROM 'object'
        THEN false ELSE coalesce(lower(payload->>'patientId')=aggregate_id::text,false) AND CASE event_type
        WHEN 'PatientRegistered' THEN jsonb_exists_all(payload,ARRAY['patientId','status','registeredAt','registeredBy'])
            AND payload - ARRAY['patientId','status','registeredAt','registeredBy']='{}'::jsonb
        WHEN 'PatientProfileUpdated' THEN jsonb_exists_all(payload,ARRAY['patientId','changedFields','updatedAt','updatedBy'])
            AND payload - ARRAY['patientId','changedFields','updatedAt','updatedBy']='{}'::jsonb
        WHEN 'PatientDeactivated' THEN jsonb_exists_all(payload,ARRAY['patientId','reasonCode','deactivatedAt','deactivatedBy'])
            AND payload - ARRAY['patientId','reasonCode','deactivatedAt','deactivatedBy']='{}'::jsonb
        ELSE true END END),
    CONSTRAINT ck_outbox_events_error CHECK (error_code IS NULL OR error_code ~ '^[A-Z][A-Z0-9_]{0,99}$'),
    CONSTRAINT ck_outbox_events_delivery CHECK (attempts>=0 AND (
        (status='PENDING' AND next_retry_at IS NOT NULL AND isfinite(next_retry_at) AND published_at IS NULL) OR
        (status='PUBLISHED' AND attempts>0 AND next_retry_at IS NULL AND error_code IS NULL
            AND published_at IS NOT NULL AND isfinite(published_at)) OR
        (status='FAILED' AND attempts>0 AND next_retry_at IS NULL AND published_at IS NULL AND error_code IS NOT NULL)))
);
