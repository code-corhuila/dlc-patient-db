-- Deliberately fake snapshots, not API registrations or deactivation transitions.
DO $$ BEGIN
    INSERT INTO patients.patient (patient_id,document_type,document_number,name,birth_date,phone,email,
        status,version,created_at,updated_at,created_by,updated_by)
    SELECT id::uuid,'CC',document,name,DATE '2000-01-01','0000000000','synthetic@example.invalid',status,1,
        '2026-01-01T00:00:00Z'::timestamptz,'2026-01-01T00:00:00Z'::timestamptz,
        'f2200000-0000-4000-8000-000000000001'::uuid,'f2200000-0000-4000-8000-000000000001'::uuid
    FROM (VALUES
        ('f2000000-0000-4000-8000-000000000001','SYNTHETIC-PAT-001','Synthetic Active','ACTIVE'),
        ('f2000000-0000-4000-8000-000000000002','SYNTHETIC-PAT-002','Synthetic Inactive','INACTIVE')
    ) p(id,document,name,status);
    INSERT INTO patients.emergency_contact (emergency_contact_id,patient_id,name,relationship,phone)
    SELECT id::uuid,'f2000000-0000-4000-8000-000000000001'::uuid,name,'Synthetic Relative','0000000000'
    FROM (VALUES
        ('f2100000-0000-4000-8000-000000000001','Synthetic Contact One'),
        ('f2100000-0000-4000-8000-000000000002','Synthetic Contact Two')
    ) c(id,name);
END; $$;
