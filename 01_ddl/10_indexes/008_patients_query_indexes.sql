DO $$
DECLARE operator_schema text;
BEGIN
    SELECT n.nspname INTO operator_schema FROM pg_catalog.pg_opclass o
    JOIN pg_catalog.pg_namespace n ON n.oid=o.opcnamespace
    JOIN pg_catalog.pg_am a ON a.oid=o.opcmethod
    JOIN pg_catalog.pg_depend d ON d.classid='pg_catalog.pg_opclass'::regclass AND d.objid=o.oid
        AND d.refclassid='pg_catalog.pg_extension'::regclass AND d.deptype='e'
    JOIN pg_catalog.pg_extension e ON e.oid=d.refobjid
    WHERE e.extname='pg_trgm' AND o.opcname='gin_trgm_ops' AND a.amname='gin'
        AND pg_catalog.has_schema_privilege(current_user,n.oid,'USAGE');
    IF operator_schema IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='55000',
            MESSAGE='Provision pg_trgm gin_trgm_ops and migrator namespace USAGE before query indexes';
    END IF;
    CREATE INDEX idx_patients_created_at_patient_id ON patients.patients (created_at,patient_id);
    CREATE INDEX idx_patients_status_created_at_patient_id ON patients.patients (status,created_at,patient_id);
    EXECUTE pg_catalog.format('CREATE INDEX idx_patients_name_document_search ON patients.patients USING gin
        (pg_catalog.lower(name) %I.gin_trgm_ops,pg_catalog.lower(document_number) %I.gin_trgm_ops)',operator_schema,operator_schema);
END;
$$;
