CREATE TABLE patients.idempotency_records (
    actor_kind text NOT NULL,
    actor_subject text NOT NULL,
    operation text NOT NULL,
    target_resource text NOT NULL,
    idempotency_key uuid NOT NULL,
    request_hash text NOT NULL,
    response_status smallint NOT NULL,
    response_body jsonb NOT NULL,
    response_location text,
    created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
    expires_at timestamptz NOT NULL DEFAULT (statement_timestamp() + INTERVAL '168 hours'),
    CONSTRAINT pk_idempotency_records PRIMARY KEY
        (actor_kind, actor_subject, operation, target_resource, idempotency_key),
    CONSTRAINT ck_idempotency_records_actor_kind CHECK (actor_kind IN ('STAFF', 'SERVICE')),
    CONSTRAINT ck_idempotency_records_actor_subject CHECK
        (char_length(actor_subject) BETWEEN 1 AND 255 AND actor_subject ~ '[^[:space:]]'),
    CONSTRAINT ck_idempotency_records_operation CHECK
        (char_length(operation) BETWEEN 1 AND 100 AND operation ~ '[^[:space:]]'),
    CONSTRAINT ck_idempotency_records_target CHECK
        (char_length(target_resource) BETWEEN 1 AND 255 AND target_resource ~ '[^[:space:]]'),
    CONSTRAINT ck_idempotency_records_hash CHECK (request_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_idempotency_records_status CHECK (response_status BETWEEN 200 AND 599),
    CONSTRAINT ck_idempotency_records_body CHECK (jsonb_typeof(response_body) = 'object'),
    CONSTRAINT ck_idempotency_records_location CHECK
        (response_location IS NULL OR (response_location ~ '[^[:space:]]' AND response_location !~ E'[\r\n]')),
    CONSTRAINT ck_idempotency_records_retention CHECK
        (isfinite(expires_at) AND expires_at >= created_at + INTERVAL '168 hours')
);
