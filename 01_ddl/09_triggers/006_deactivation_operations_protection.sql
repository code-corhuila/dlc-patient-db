CREATE TRIGGER trg_deactivation_operations_write
BEFORE INSERT OR UPDATE OR DELETE ON patients.deactivation_operations FOR EACH ROW
EXECUTE FUNCTION patients.protect_deactivation_operations();
CREATE TRIGGER trg_deactivation_operations_truncate BEFORE TRUNCATE ON patients.deactivation_operations FOR EACH STATEMENT
EXECUTE FUNCTION patients.protect_deactivation_operations();
