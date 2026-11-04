DO $$ BEGIN
    IF current_user<>'patients_runtime' OR session_user<>'patients_runtime' THEN
        RAISE EXCEPTION 'Verify seeds through an authenticated runtime';
    END IF;
    IF (SELECT count(*) FROM patients.patient)<>2 OR
       (SELECT count(*) FROM patients.emergency_contact)<>2 THEN
        RAISE EXCEPTION 'Expected two synthetic profiles and two contacts';
    END IF;
    IF NOT EXISTS (SELECT FROM patients.patient WHERE patient_id='f2000000-0000-4000-8000-000000000001'
        AND status='ACTIVE' AND document_number='SYNTHETIC-PAT-001' AND email='synthetic@example.invalid') OR
       NOT EXISTS (SELECT FROM patients.patient WHERE patient_id='f2000000-0000-4000-8000-000000000002'
        AND status='INACTIVE' AND document_number='SYNTHETIC-PAT-002' AND version=1) THEN
        RAISE EXCEPTION 'Synthetic identities or states differ';
    END IF;
    IF (SELECT count(*) FROM patients.emergency_contact
        WHERE patient_id='f2000000-0000-4000-8000-000000000001')<>2 OR
       EXISTS (SELECT FROM patients.emergency_contact
        WHERE patient_id='f2000000-0000-4000-8000-000000000002') THEN
        RAISE EXCEPTION 'Synthetic contact cardinality differs';
    END IF;
    IF EXISTS (SELECT FROM patients.patient_audit) OR EXISTS (SELECT FROM patients.outbox_event) OR
       EXISTS (SELECT FROM patients.inbox_event) OR EXISTS (SELECT FROM patients.idempotency_record) OR
       EXISTS (SELECT FROM patients.deactivation_operation) THEN
        RAISE EXCEPTION 'Seeds fabricated lifecycle or integration facts';
    END IF;
END; $$;
ROLLBACK;
