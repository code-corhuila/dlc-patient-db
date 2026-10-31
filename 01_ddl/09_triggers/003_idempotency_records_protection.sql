CREATE TRIGGER trg_idempotency_records_write
BEFORE INSERT OR UPDATE OR DELETE ON patients.idempotency_records FOR EACH ROW
EXECUTE FUNCTION patients.protect_idempotency_records();
CREATE TRIGGER trg_idempotency_records_truncate
BEFORE TRUNCATE ON patients.idempotency_records FOR EACH STATEMENT
EXECUTE FUNCTION patients.protect_idempotency_records();
