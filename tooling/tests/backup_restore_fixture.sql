-- Persist only in the uniquely named disposable source; never a deployment seed.
SELECT pg_temp.register_patient(99,'CC','RECOVERY-99');
INSERT INTO patients.emergency_contact VALUES ('20000000-0000-4000-8000-000000000099',
    '00000000-0000-4000-8000-000000000099','Synthetic Recovery Contact','Relative','3000000000');
INSERT INTO patients.patient_audit (audit_id,patient_id,actor_id,action,patient_version,changed_fields)
VALUES ('30000000-0000-4000-8000-000000000099','00000000-0000-4000-8000-000000000099',
    '10000000-0000-4000-8000-000000000001','REGISTERED',1,'{}');
INSERT INTO patients.idempotency_record (actor_kind,actor_subject,operation,target_resource,
    idempotency_key,request_hash,response_status,response_body,response_location)
VALUES ('STAFF','10000000-0000-4000-8000-000000000001','register','/patients',
    '40000000-0000-4000-8000-000000000099',repeat('a',64),201,
    '{"id":"00000000-0000-4000-8000-000000000099"}','/api/v1/patients/00000000-0000-4000-8000-000000000099');
INSERT INTO patients.outbox_event (event_id,aggregate_id,event_type,occurred_at,payload,correlation_id,causation_id)
VALUES ('50000000-0000-4000-8000-000000000099','00000000-0000-4000-8000-000000000099',
    'PatientRegistered','2026-01-01T00:00:00Z','{"patientId":"00000000-0000-4000-8000-000000000099",
    "status":"ACTIVE","registeredAt":"2026-01-01T00:00:00Z","registeredBy":"10000000-0000-4000-8000-000000000001"}',
    '60000000-0000-4000-8000-000000000099','70000000-0000-4000-8000-000000000099');
SELECT pg_temp.receive_assignment('80000000-0000-4000-8000-000000000099');
INSERT INTO patients.deactivation_operation (operation_id,patient_id,actor_id,idempotency_key,expected_version,reason_code,reason)
VALUES ('b1000000-0000-4000-8000-000000000099','00000000-0000-4000-8000-000000000099',
    '10000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000099',1,'ADMINISTRATIVE','Synthetic recovery intent');
UPDATE patients.deactivation_operation SET guard_id='d1000000-0000-4000-8000-000000000099',guard_token_hash=repeat('b',64);
COMMIT;
