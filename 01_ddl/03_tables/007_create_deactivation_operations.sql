CREATE TABLE patients.deactivation_operations (
    operation_id uuid CONSTRAINT pk_deactivation_operations PRIMARY KEY,
    patient_id uuid NOT NULL,
    actor_id uuid NOT NULL,
    idempotency_key uuid NOT NULL,
    expected_version integer NOT NULL,
    reason text NOT NULL,
    guard_id uuid,
    guard_token_hash text,
    outcome text NOT NULL DEFAULT 'PENDING',
    operation_version bigint NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT statement_timestamp(),
    completed_at timestamptz,
    CONSTRAINT ck_deactivation_operations_version CHECK (expected_version>0 AND operation_version>0),
    CONSTRAINT ck_deactivation_operations_reason CHECK (char_length(reason) BETWEEN 1 AND 1000 AND reason ~ '[^[:space:]]'),
    CONSTRAINT ck_deactivation_operations_guard CHECK ((guard_id IS NULL)=(guard_token_hash IS NULL)
        AND (guard_token_hash IS NULL OR guard_token_hash ~ '^[0-9a-f]{64}$')),
    CONSTRAINT ck_deactivation_operations_outcome CHECK (
        (outcome='PENDING' AND completed_at IS NULL) OR
        (outcome='FINALIZED' AND guard_id IS NOT NULL AND completed_at IS NOT NULL AND isfinite(completed_at)) OR
        (outcome='ABORTED' AND completed_at IS NOT NULL AND isfinite(completed_at)))
);
