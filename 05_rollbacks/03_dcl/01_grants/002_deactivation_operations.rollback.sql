REVOKE SELECT, INSERT ON patients.deactivation_operations FROM patients_runtime;
REVOKE UPDATE (guard_id,guard_token_hash,outcome) ON patients.deactivation_operations FROM patients_runtime;
