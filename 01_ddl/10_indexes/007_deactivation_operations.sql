CREATE UNIQUE INDEX uk_deactivation_operations_request ON patients.deactivation_operations (actor_id,patient_id,idempotency_key);
CREATE UNIQUE INDEX uk_deactivation_operations_guard ON patients.deactivation_operations (guard_id);
CREATE INDEX idx_deactivation_operations_patient_created_at ON patients.deactivation_operations (patient_id,created_at,operation_id);
CREATE INDEX idx_deactivation_operations_pending ON patients.deactivation_operations (created_at,operation_id) WHERE outcome='PENDING';
