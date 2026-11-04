CREATE FUNCTION pg_temp.expect_denied(statement text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    BEGIN EXECUTE statement;
    EXCEPTION WHEN insufficient_privilege THEN RETURN;
    END;
    RAISE EXCEPTION 'Expected SQLSTATE 42501 for %',statement;
END; $$;
DO $$
BEGIN
    IF current_user<>'patients_app' OR session_user<>'patients_app' THEN
        RAISE EXCEPTION 'Domain role checks must authenticate as patients_app';
    END IF;
    IF NOT pg_has_role('patients_app','patients_writer','MEMBER') THEN
        RAISE EXCEPTION 'patients_app must hold patients_writer';
    END IF;
    IF EXISTS (SELECT FROM pg_roles WHERE rolname IN ('patients_reader','patients_writer') AND rolcanlogin) THEN
        RAISE EXCEPTION 'Domain roles must not log in';
    END IF;
    PERFORM count(*) FROM patients.patient;
END;
$$;
SELECT pg_temp.expect_denied('CREATE TABLE patients.app_ddl_probe (id integer)');
SELECT pg_temp.expect_denied('TRUNCATE patients.patient');
SET LOCAL ROLE patients_reader;
SELECT count(*) FROM patients.patient;
SELECT count(*) FROM patients.emergency_contact;
SELECT pg_temp.expect_denied('SELECT count(*) FROM patients.outbox_event');
SELECT pg_temp.expect_denied('DELETE FROM patients.emergency_contact');
RESET ROLE;
