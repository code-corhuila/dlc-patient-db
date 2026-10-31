CREATE TRIGGER trg_inbox_events_write
BEFORE INSERT OR UPDATE OR DELETE ON patients.inbox_events FOR EACH ROW
EXECUTE FUNCTION patients.protect_inbox_events();
CREATE TRIGGER trg_inbox_events_truncate BEFORE TRUNCATE ON patients.inbox_events FOR EACH STATEMENT
EXECUTE FUNCTION patients.protect_inbox_events();
