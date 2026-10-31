CREATE FUNCTION patients.protect_idempotency_records() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.created_at := statement_timestamp();
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        IF clock_timestamp() >= OLD.expires_at THEN RETURN OLD; END IF;
        RAISE EXCEPTION USING ERRCODE = '23514', CONSTRAINT = 'ck_idempotency_records_retention',
            MESSAGE = 'Retry retention has not elapsed';
    END IF;
    RAISE EXCEPTION USING ERRCODE = '23514', CONSTRAINT = 'ck_idempotency_records_immutable',
        MESSAGE = 'Original request outcomes are immutable';
END;
$$;
