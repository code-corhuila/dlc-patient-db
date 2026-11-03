-- Atomic reversal only of exact seed snapshots; never erase evolved or referenced data.
DO $$ BEGIN
    DELETE FROM patients.emergency_contacts
    WHERE patient_id='f2000000-0000-4000-8000-000000000001'
      AND relationship='Synthetic Relative' AND phone='0000000000'
      AND (emergency_contact_id,name) IN (VALUES
        ('f2100000-0000-4000-8000-000000000001'::uuid,'Synthetic Contact One'),
        ('f2100000-0000-4000-8000-000000000002'::uuid,'Synthetic Contact Two'));
    DELETE FROM patients.patients
    WHERE document_type='CC' AND birth_date=DATE '2000-01-01' AND phone='0000000000'
      AND email='synthetic@example.invalid' AND address IS NULL AND version=1
      AND created_at='2026-01-01T00:00:00Z'::timestamptz AND updated_at='2026-01-01T00:00:00Z'::timestamptz
      AND created_by='f2200000-0000-4000-8000-000000000001' AND updated_by=created_by
      AND (patient_id,document_number,name,status) IN (VALUES
        ('f2000000-0000-4000-8000-000000000001'::uuid,'SYNTHETIC-PAT-001','Synthetic Active','ACTIVE'),
        ('f2000000-0000-4000-8000-000000000002'::uuid,'SYNTHETIC-PAT-002','Synthetic Inactive','INACTIVE'));
    IF EXISTS (SELECT FROM patients.patients WHERE patient_id IN
        ('f2000000-0000-4000-8000-000000000001','f2000000-0000-4000-8000-000000000002')) OR
       EXISTS (SELECT FROM patients.emergency_contacts WHERE emergency_contact_id IN
        ('f2100000-0000-4000-8000-000000000001','f2100000-0000-4000-8000-000000000002')) THEN
        RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='Synthetic snapshots changed; use reviewed forward recovery';
    END IF;
END; $$;
