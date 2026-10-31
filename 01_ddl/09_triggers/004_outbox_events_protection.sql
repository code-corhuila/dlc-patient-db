CREATE TRIGGER trg_outbox_events_write
BEFORE INSERT OR UPDATE OR DELETE ON patients.outbox_events FOR EACH ROW
EXECUTE FUNCTION patients.protect_outbox_events();
CREATE TRIGGER trg_outbox_events_truncate BEFORE TRUNCATE ON patients.outbox_events FOR EACH STATEMENT
EXECUTE FUNCTION patients.protect_outbox_events();
