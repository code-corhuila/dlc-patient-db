CREATE OR REPLACE FUNCTION patients.reject_patient_id_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION USING ERRCODE = '23514',
        CONSTRAINT = 'chk_patient_identity_immutable',
        MESSAGE = 'Patient identifier is immutable';
END;
$$;
CREATE OR REPLACE FUNCTION patients.protect_patient_audit() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.recorded_at := statement_timestamp();
        RETURN NEW;
    END IF;
    RAISE EXCEPTION USING ERRCODE = '23514', CONSTRAINT = 'chk_patient_audit_append_only',
        MESSAGE = 'Patient audit is append-only';
END;
$$;
CREATE OR REPLACE FUNCTION patients.protect_idempotency_records() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.created_at := statement_timestamp();
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        IF clock_timestamp() >= OLD.expires_at THEN RETURN OLD; END IF;
        RAISE EXCEPTION USING ERRCODE = '23514', CONSTRAINT = 'chk_idempotency_record_retention',
            MESSAGE = 'Retry retention has not elapsed';
    END IF;
    RAISE EXCEPTION USING ERRCODE = '23514', CONSTRAINT = 'chk_idempotency_record_immutable',
        MESSAGE = 'Original request outcomes are immutable';
END;
$$;
CREATE OR REPLACE FUNCTION patients.protect_outbox_events() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='INSERT' THEN
        NEW.recorded_at := statement_timestamp();
        IF NEW.status IS NOT NULL AND NEW.attempts IS NOT NULL AND
            (NEW.status<>'PENDING' OR NEW.attempts<>0 OR NEW.published_at IS NOT NULL OR NEW.error_code IS NOT NULL) THEN
            RAISE EXCEPTION USING ERRCODE='23514',CONSTRAINT='chk_outbox_event_initial',MESSAGE='Events start pending';
        END IF;
    ELSIF TG_OP='UPDATE' THEN
        IF ROW(NEW.event_id,NEW.aggregate_id,NEW.event_type,NEW.aggregate_type,NEW.event_version,NEW.producer,
            NEW.occurred_at,NEW.recorded_at,NEW.payload,NEW.correlation_id,NEW.causation_id,NEW.actor_user_id)
            IS DISTINCT FROM ROW(OLD.event_id,OLD.aggregate_id,OLD.event_type,OLD.aggregate_type,OLD.event_version,
            OLD.producer,OLD.occurred_at,OLD.recorded_at,OLD.payload,OLD.correlation_id,OLD.causation_id,OLD.actor_user_id) THEN
            RAISE EXCEPTION USING ERRCODE='23514',CONSTRAINT='chk_outbox_event_immutable',MESSAGE='Event facts are immutable';
        END IF;
        IF OLD.status='PUBLISHED' OR NEW.attempts<OLD.attempts THEN
            RAISE EXCEPTION USING ERRCODE='23514',CONSTRAINT='chk_outbox_event_delivery',MESSAGE='Invalid publication transition';
        END IF;
        IF NEW.status='PUBLISHED' THEN NEW.published_at := statement_timestamp(); END IF;
    ELSE
        RAISE EXCEPTION USING ERRCODE='23514',CONSTRAINT='chk_outbox_event_immutable',MESSAGE='Event history is retained';
    END IF;
    RETURN NEW;
END;
$$;
CREATE OR REPLACE FUNCTION patients.protect_inbox_events() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='INSERT' THEN
        NEW.recorded_at := statement_timestamp();
        IF NEW.status IS NOT NULL AND NEW.attempts IS NOT NULL AND
            (NEW.status<>'PENDING' OR NEW.attempts<>0 OR NEW.processed_at IS NOT NULL OR NEW.error_code IS NOT NULL) THEN
            RAISE EXCEPTION USING ERRCODE='23514',CONSTRAINT='chk_inbox_event_initial',MESSAGE='Events start pending';
        END IF;
    ELSIF TG_OP='UPDATE' THEN
        IF ROW(NEW.event_id,NEW.aggregate_id,NEW.event_type,NEW.aggregate_type,NEW.event_version,NEW.producer,
            NEW.assignment_version,NEW.occurred_at,NEW.recorded_at,NEW.payload,NEW.correlation_id,NEW.causation_id,NEW.actor_user_id)
            IS DISTINCT FROM ROW(OLD.event_id,OLD.aggregate_id,OLD.event_type,OLD.aggregate_type,OLD.event_version,
            OLD.producer,OLD.assignment_version,OLD.occurred_at,OLD.recorded_at,OLD.payload,OLD.correlation_id,OLD.causation_id,OLD.actor_user_id) THEN
            RAISE EXCEPTION USING ERRCODE='23514',CONSTRAINT='chk_inbox_event_immutable',MESSAGE='Event facts are immutable';
        END IF;
        IF OLD.status='PROCESSED' OR NEW.attempts<OLD.attempts THEN
            RAISE EXCEPTION USING ERRCODE='23514',CONSTRAINT='chk_inbox_event_delivery',MESSAGE='Invalid processing transition';
        END IF;
        IF NEW.status='PROCESSED' THEN NEW.processed_at := statement_timestamp(); END IF;
    ELSE
        RAISE EXCEPTION USING ERRCODE='23514',CONSTRAINT='chk_inbox_event_immutable',MESSAGE='Event history is retained';
    END IF;
    RETURN NEW;
END;
$$;
CREATE OR REPLACE FUNCTION patients.protect_deactivation_operations() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='INSERT' THEN
        NEW.created_at := statement_timestamp(); NEW.updated_at := NEW.created_at; NEW.operation_version := 1;
        IF NEW.outcome IS NOT NULL AND (NEW.outcome<>'PENDING' OR NEW.guard_id IS NOT NULL OR
            NEW.guard_token_hash IS NOT NULL OR NEW.completed_at IS NOT NULL) THEN
            RAISE EXCEPTION USING ERRCODE='23514',CONSTRAINT='chk_deactivation_operation_initial',MESSAGE='Persist intent before guard acquisition';
        END IF;
    ELSIF TG_OP='UPDATE' THEN
        IF ROW(NEW.operation_id,NEW.patient_id,NEW.actor_id,NEW.idempotency_key,NEW.expected_version,NEW.reason,
               NEW.created_at,NEW.updated_at,NEW.completed_at,NEW.operation_version) IS DISTINCT FROM
           ROW(OLD.operation_id,OLD.patient_id,OLD.actor_id,OLD.idempotency_key,OLD.expected_version,OLD.reason,
               OLD.created_at,OLD.updated_at,OLD.completed_at,OLD.operation_version) OR
           (OLD.guard_id IS NOT NULL AND NEW.guard_id IS DISTINCT FROM OLD.guard_id) THEN
            RAISE EXCEPTION USING ERRCODE='23514',CONSTRAINT='chk_deactivation_operation_immutable',MESSAGE='Operation identity and facts are immutable';
        END IF;
        IF OLD.outcome<>'PENDING' AND NEW.outcome IS DISTINCT FROM OLD.outcome THEN
            RAISE EXCEPTION USING ERRCODE='23514',CONSTRAINT='chk_deactivation_operation_transition',MESSAGE='Local terminal outcome cannot change';
        END IF;
        IF OLD.outcome='PENDING' AND NEW.outcome IN ('FINALIZED','ABORTED') THEN NEW.completed_at := statement_timestamp(); END IF;
        NEW.updated_at := statement_timestamp(); NEW.operation_version := OLD.operation_version+1;
    ELSE
        RAISE EXCEPTION USING ERRCODE='23514',CONSTRAINT='chk_deactivation_operation_immutable',MESSAGE='Retain operation proof for recovery';
    END IF;
    RETURN NEW;
END;
$$;
ALTER FUNCTION patients.protect_idempotency_records() RENAME TO protect_idempotency_record;
ALTER FUNCTION patients.protect_outbox_events() RENAME TO protect_outbox_event;
ALTER FUNCTION patients.protect_inbox_events() RENAME TO protect_inbox_event;
ALTER FUNCTION patients.protect_deactivation_operations() RENAME TO protect_deactivation_operation;
