CREATE TABLE patients.patient_audit (
    audit_id uuid CONSTRAINT pk_patient_audit PRIMARY KEY,
    patient_id uuid NOT NULL,
    actor_id uuid NOT NULL,
    action text NOT NULL,
    patient_version integer NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT statement_timestamp(),
    changed_fields text[] NOT NULL DEFAULT '{}',
    reason text,
    CONSTRAINT ck_patient_audit_action CHECK (action IN ('REGISTERED', 'PROFILE_UPDATED', 'DEACTIVATED')),
    CONSTRAINT ck_patient_audit_version CHECK (patient_version > 0),
    CONSTRAINT ck_patient_audit_changed_fields CHECK (
        CASE WHEN coalesce(array_ndims(changed_fields), 1) <> 1 THEN false
        ELSE array_position(changed_fields, NULL) IS NULL AND changed_fields <@
            ARRAY['documentType', 'documentNumber', 'name', 'birthDate', 'phone', 'email',
                  'address', 'emergencyContacts', 'status']::text[] END),
    CONSTRAINT ck_patient_audit_reason CHECK
        (reason IS NULL OR (char_length(reason) BETWEEN 1 AND 1000 AND reason ~ '[^[:space:]]')),
    CONSTRAINT ck_patient_audit_deactivation_reason CHECK (action <> 'DEACTIVATED' OR reason IS NOT NULL)
);
