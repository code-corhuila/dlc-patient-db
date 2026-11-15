CREATE FUNCTION patients.require_deactivation_proof() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_TABLE_NAME='patient' THEN
        IF NOT EXISTS (SELECT FROM patients.patient_audit a WHERE a.patient_id=NEW.patient_id
                AND a.action='DEACTIVATED' AND a.patient_version=NEW.version)
            OR NOT EXISTS (SELECT FROM patients.outbox_event e WHERE e.aggregate_id=NEW.patient_id
                AND e.event_type='PatientDeactivated')
            OR NOT EXISTS (SELECT FROM patients.deactivation_operation o WHERE o.patient_id=NEW.patient_id
                AND o.outcome='FINALIZED' AND o.expected_version=OLD.version) THEN
            RAISE EXCEPTION USING ERRCODE='23514',CONSTRAINT='chk_patient_deactivation_proof',
                MESSAGE='Deactivation commits with its audit, PatientDeactivated event and finalized operation';
        END IF;
    ELSIF NOT EXISTS (SELECT FROM patients.patient p WHERE p.patient_id=NEW.patient_id
            AND p.status='INACTIVE' AND p.version=NEW.expected_version+1) THEN
        RAISE EXCEPTION USING ERRCODE='23514',CONSTRAINT='chk_deactivation_operation_proof',
            MESSAGE='A finalized operation commits with the deactivated profile version';
    END IF;
    RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER trg_patient_deactivation_proof
AFTER UPDATE OF status ON patients.patient DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
WHEN (OLD.status='ACTIVE' AND NEW.status='INACTIVE')
EXECUTE FUNCTION patients.require_deactivation_proof();
CREATE CONSTRAINT TRIGGER trg_deactivation_operation_proof
AFTER UPDATE OF outcome ON patients.deactivation_operation DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
WHEN (OLD.outcome<>'FINALIZED' AND NEW.outcome='FINALIZED')
EXECUTE FUNCTION patients.require_deactivation_proof();
