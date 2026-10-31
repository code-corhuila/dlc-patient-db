CREATE FUNCTION patients.protect_outbox_events() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='INSERT' THEN
        NEW.recorded_at := statement_timestamp();
        IF NEW.status IS NOT NULL AND NEW.attempts IS NOT NULL AND
            (NEW.status<>'PENDING' OR NEW.attempts<>0 OR NEW.published_at IS NOT NULL OR NEW.error_code IS NOT NULL) THEN
            RAISE EXCEPTION USING ERRCODE='23514',CONSTRAINT='ck_outbox_events_initial',MESSAGE='Events start pending';
        END IF;
    ELSIF TG_OP='UPDATE' THEN
        IF ROW(NEW.event_id,NEW.aggregate_id,NEW.event_type,NEW.aggregate_type,NEW.event_version,NEW.producer,
            NEW.occurred_at,NEW.recorded_at,NEW.payload,NEW.correlation_id,NEW.causation_id,NEW.actor_user_id)
            IS DISTINCT FROM ROW(OLD.event_id,OLD.aggregate_id,OLD.event_type,OLD.aggregate_type,OLD.event_version,
            OLD.producer,OLD.occurred_at,OLD.recorded_at,OLD.payload,OLD.correlation_id,OLD.causation_id,OLD.actor_user_id) THEN
            RAISE EXCEPTION USING ERRCODE='23514',CONSTRAINT='ck_outbox_events_immutable',MESSAGE='Event facts are immutable';
        END IF;
        IF OLD.status='PUBLISHED' OR NEW.attempts<OLD.attempts THEN
            RAISE EXCEPTION USING ERRCODE='23514',CONSTRAINT='ck_outbox_events_delivery',MESSAGE='Invalid publication transition';
        END IF;
        IF NEW.status='PUBLISHED' THEN NEW.published_at := statement_timestamp(); END IF;
    ELSE
        RAISE EXCEPTION USING ERRCODE='23514',CONSTRAINT='ck_outbox_events_immutable',MESSAGE='Event history is retained';
    END IF;
    RETURN NEW;
END;
$$;
