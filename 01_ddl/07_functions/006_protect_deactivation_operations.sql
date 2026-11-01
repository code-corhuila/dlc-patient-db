CREATE FUNCTION patients.protect_deactivation_operations() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='INSERT' THEN
        NEW.created_at := statement_timestamp(); NEW.updated_at := NEW.created_at; NEW.operation_version := 1;
        IF NEW.outcome IS NOT NULL AND (NEW.outcome<>'PENDING' OR NEW.guard_id IS NOT NULL OR
            NEW.guard_token_hash IS NOT NULL OR NEW.completed_at IS NOT NULL) THEN
            RAISE EXCEPTION USING ERRCODE='23514',CONSTRAINT='ck_deactivation_operations_initial',MESSAGE='Persist intent before guard acquisition';
        END IF;
    ELSIF TG_OP='UPDATE' THEN
        IF ROW(NEW.operation_id,NEW.patient_id,NEW.actor_id,NEW.idempotency_key,NEW.expected_version,NEW.reason,
               NEW.created_at,NEW.updated_at,NEW.completed_at,NEW.operation_version) IS DISTINCT FROM
           ROW(OLD.operation_id,OLD.patient_id,OLD.actor_id,OLD.idempotency_key,OLD.expected_version,OLD.reason,
               OLD.created_at,OLD.updated_at,OLD.completed_at,OLD.operation_version) OR
           (OLD.guard_id IS NOT NULL AND NEW.guard_id IS DISTINCT FROM OLD.guard_id) THEN
            RAISE EXCEPTION USING ERRCODE='23514',CONSTRAINT='ck_deactivation_operations_immutable',MESSAGE='Operation identity and facts are immutable';
        END IF;
        IF OLD.outcome<>'PENDING' AND NEW.outcome IS DISTINCT FROM OLD.outcome THEN
            RAISE EXCEPTION USING ERRCODE='23514',CONSTRAINT='ck_deactivation_operations_transition',MESSAGE='Local terminal outcome cannot change';
        END IF;
        IF OLD.outcome='PENDING' AND NEW.outcome IN ('FINALIZED','ABORTED') THEN NEW.completed_at := statement_timestamp(); END IF;
        NEW.updated_at := statement_timestamp(); NEW.operation_version := OLD.operation_version+1;
    ELSE
        RAISE EXCEPTION USING ERRCODE='23514',CONSTRAINT='ck_deactivation_operations_immutable',MESSAGE='Retain operation proof for recovery';
    END IF;
    RETURN NEW;
END;
$$;
