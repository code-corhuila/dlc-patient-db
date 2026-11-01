GRANT SELECT, INSERT ON patients.deactivation_operations TO patients_runtime;
GRANT UPDATE (guard_id,guard_token_hash,outcome) ON patients.deactivation_operations TO patients_runtime;
