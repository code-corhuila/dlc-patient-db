-- Representative synthetic data, with timestamp ties and skewed status distribution.
INSERT INTO patients.patients (patient_id,document_type,document_number,name,birth_date,phone,email,status,
    created_at,updated_at,created_by,updated_by)
SELECT ('e1000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'CC','QUERY-'||n,
    'Synthetic Query '||n,'2000-01-01','3000000000','query@example.invalid',
    CASE WHEN n%50=0 THEN 'INACTIVE' ELSE 'ACTIVE' END,
    '2025-01-01T00:00:00Z'::timestamptz+(n/50)*interval '1 second','2025-01-01T00:00:00Z'::timestamptz,
    '10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001'
FROM generate_series(1,20000) n;
UPDATE patients.patients SET name=U&'Paciente \00C1lvarez Needle' WHERE document_number='QUERY-100';
UPDATE patients.patients SET name='Literal%_'||chr(92)||'Tail' WHERE document_number='QUERY-101';
UPDATE patients.patients SET document_number='ID-Needle-102' WHERE document_number='QUERY-102';
UPDATE patients.patients SET email='needle@example.invalid' WHERE document_number='QUERY-103';
ANALYZE patients.patients;
SELECT pg_catalog.gin_clean_pending_list('patients.idx_patients_name_document_search'::regclass);
CREATE FUNCTION pg_temp.literal_pattern(term text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT '%'||replace(replace(replace(lower(term),chr(92),chr(92)||chr(92)),'%',chr(92)||'%'),'_',chr(92)||'_')||'%';
$$;
CREATE FUNCTION pg_temp.require_query_index(query text, expected_index text, ordered boolean DEFAULT true, alternative text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE observed jsonb; used boolean; sorted boolean; indexes text[];
BEGIN
    EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) '||query INTO observed;
    WITH RECURSIVE nodes(node) AS (
        SELECT observed->0->'Plan' UNION ALL
        SELECT child FROM nodes CROSS JOIN LATERAL jsonb_array_elements(coalesce(node->'Plans','[]')) child
    ) SELECT bool_or(node->>'Index Name' IN (expected_index,alternative)),
        bool_or(node->>'Node Type' IN ('Sort','Incremental Sort')),
        array_agg(DISTINCT node->>'Index Name') FILTER (WHERE node->>'Index Name' IS NOT NULL)
        INTO used,sorted,indexes FROM nodes;
    IF NOT coalesce(used,false) OR (ordered AND sorted) THEN
        RAISE EXCEPTION 'Expected ordered index %; observed plan %',expected_index,observed;
    END IF;
    RETURN jsonb_build_object('indexes',indexes,'rows',observed->0->'Plan'->'Actual Rows',
        'shared_hits',observed->0->'Plan'->'Shared Hit Blocks','sorted',coalesce(sorted,false));
END; $$;
SET LOCAL ROLE patients_runtime;
SELECT pg_temp.require_query_index('SELECT patient_id FROM patients.patients ORDER BY created_at,patient_id LIMIT 20 OFFSET 40',
    'idx_patients_created_at_patient_id');
SELECT pg_temp.require_query_index($q$SELECT patient_id FROM patients.patients WHERE status='INACTIVE'
    ORDER BY created_at,patient_id LIMIT 20 OFFSET 40$q$,'idx_patients_status_created_at_patient_id');
SELECT pg_temp.require_query_index($q$SELECT patient_id FROM patients.patients WHERE status='ACTIVE'
    ORDER BY created_at,patient_id LIMIT 20$q$,'idx_patients_status_created_at_patient_id',true,'idx_patients_created_at_patient_id');
SELECT pg_temp.require_query_index($q$SELECT patient_id FROM patients.patients
    WHERE lower(name) LIKE '%needle%' OR lower(document_number) LIKE '%needle%'
    ORDER BY created_at,patient_id LIMIT 20$q$,'idx_patients_name_document_search',false);
DO $$ DECLARE found integer;
BEGIN
    SELECT count(*) INTO found FROM patients.patients WHERE lower(name) LIKE pg_temp.literal_pattern('NEEDLE')
        OR lower(document_number) LIKE pg_temp.literal_pattern('NEEDLE');
    IF found<>2 THEN RAISE EXCEPTION 'Name/document substring or case handling failed'; END IF;
    SELECT count(*) INTO found FROM patients.patients WHERE patient_id='e1000000-0000-4000-8000-000000000100'
        AND status='INACTIVE' AND (lower(name) LIKE '%needle%' OR lower(document_number) LIKE '%needle%');
    IF found<>1 THEN RAISE EXCEPTION 'Scoped search count leaked another patient'; END IF;
    SELECT count(*) INTO found FROM patients.patients WHERE lower(name) LIKE pg_temp.literal_pattern('3000000000')
        OR lower(document_number) LIKE pg_temp.literal_pattern('3000000000');
    IF found<>0 THEN RAISE EXCEPTION 'Phone-only matches were included'; END IF;
    SELECT count(*) INTO found FROM patients.patients WHERE lower(name) LIKE pg_temp.literal_pattern(U&'\00C1LVAREZ');
    IF found<>1 THEN RAISE EXCEPTION 'Accented case handling failed'; END IF;
    SELECT count(*) INTO found FROM patients.patients WHERE lower(name) LIKE pg_temp.literal_pattern('alvarez');
    IF found<>0 THEN RAISE EXCEPTION 'Accents were removed'; END IF;
    SELECT count(*) INTO found FROM patients.patients WHERE lower(name) LIKE pg_temp.literal_pattern('%_'||chr(92)) ESCAPE chr(92);
    IF found<>1 THEN RAISE EXCEPTION 'LIKE metacharacters were not literal'; END IF;
    SELECT count(*) INTO found FROM patients.patients WHERE lower(name) LIKE pg_temp.literal_pattern(U&'\00E1');
    IF found<>1 THEN RAISE EXCEPTION 'One-character search failed'; END IF;
    -- The assigned record matches only by document: Dentist name-only search must not expose it.
    SELECT count(*) INTO found FROM patients.patients WHERE patient_id='e1000000-0000-4000-8000-000000000102'
        AND lower(name) LIKE pg_temp.literal_pattern('needle');
    IF found<>0 THEN RAISE EXCEPTION 'Document leaked through care search'; END IF;
END; $$;
-- Apply the authorized identifier scope before counting and pagination.
DO $$ DECLARE ids uuid[]; actual uuid[]; total integer;
BEGIN
    SELECT array_agg(('e1000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid ORDER BY n)
        INTO ids FROM generate_series(51,70) n;
    SELECT count(*) INTO total FROM patients.patients WHERE patient_id=ANY(ids) AND status='ACTIVE';
    SELECT array_agg(patient_id ORDER BY created_at,patient_id) INTO actual FROM (
        SELECT patient_id,created_at FROM patients.patients WHERE patient_id=ANY(ids) AND status='ACTIVE'
        ORDER BY created_at,patient_id LIMIT 5 OFFSET 5) page;
    IF total<>20 OR actual IS DISTINCT FROM ids[6:10] THEN RAISE EXCEPTION 'Scoped stable pagination failed'; END IF;
    SELECT array_agg(patient_id ORDER BY created_at,patient_id) INTO actual FROM (
        SELECT patient_id,created_at FROM patients.patients WHERE patient_id=ANY(ids)
        ORDER BY created_at,patient_id LIMIT 5 OFFSET 100) page;
    IF actual IS NOT NULL THEN RAISE EXCEPTION 'Beyond-last page was not empty'; END IF;
END; $$;
ROLLBACK;
