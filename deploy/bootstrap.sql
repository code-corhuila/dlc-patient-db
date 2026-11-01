-- Run as the authorized platform DBA in the selected database; credentials are external.
-- One transaction: repeat safely, refuse foreign ownership, never adopt an existing installation.
DO $$
DECLARE role_name text; table_name text;
BEGIN
    FOREACH role_name IN ARRAY ARRAY['patients_migrator','patients_runtime'] LOOP
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname=role_name) THEN
            EXECUTE format('CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',role_name);
        END IF;
        IF EXISTS (SELECT FROM pg_roles r WHERE rolname=role_name AND
            (NOT rolcanlogin OR rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls OR
             EXISTS (SELECT FROM pg_auth_members m WHERE m.member=r.oid))) THEN
            RAISE EXCEPTION 'Unsafe role: %',role_name;
        END IF;
        IF has_schema_privilege(role_name,'public','CREATE') OR
            (role_name='patients_runtime' AND has_database_privilege(role_name,current_database(),'CREATE')) THEN
            RAISE EXCEPTION 'Unexpected CREATE privilege: %',role_name;
        END IF;
    END LOOP;
    IF EXISTS (SELECT FROM pg_namespace WHERE nspname='patients' AND
        pg_get_userbyid(nspowner)<>'patients_migrator') OR
       EXISTS (SELECT FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='patients' AND pg_get_userbyid(c.relowner)<>'patients_migrator') OR
       EXISTS (SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='patients' AND pg_get_userbyid(p.proowner)<>'patients_migrator') THEN
        RAISE EXCEPTION 'Patients objects have another owner; review ownership migration separately';
    END IF;
    FOREACH table_name IN ARRAY ARRAY['databasechangelog_patients','databasechangeloglock_patients'] LOOP
        IF EXISTS (SELECT FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='public' AND c.relname=table_name AND
            (c.relkind<>'r' OR pg_get_userbyid(c.relowner)<>'patients_migrator')) THEN
            RAISE EXCEPTION 'Unexpected Liquibase object or owner: %',table_name;
        END IF;
    END LOOP;
    -- Preserve the existing Liquibase identity/location; no public CREATE for the migrator.
    CREATE TABLE IF NOT EXISTS public.databasechangelog_patients (
        id varchar(255) NOT NULL, author varchar(255) NOT NULL, filename varchar(255) NOT NULL,
        dateexecuted timestamp NOT NULL, orderexecuted integer NOT NULL, exectype varchar(10) NOT NULL,
        md5sum varchar(35), description varchar(255), comments varchar(255), tag varchar(255),
        liquibase varchar(20), contexts varchar(255), labels varchar(255), deployment_id varchar(10)
    );
    CREATE TABLE IF NOT EXISTS public.databasechangeloglock_patients (
        id integer PRIMARY KEY, locked boolean NOT NULL, lockgranted timestamp, lockedby varchar(255)
    );
    ALTER TABLE public.databasechangelog_patients OWNER TO patients_migrator;
    ALTER TABLE public.databasechangeloglock_patients OWNER TO patients_migrator;
    INSERT INTO public.databasechangeloglock_patients (id,locked) VALUES (1,false) ON CONFLICT (id) DO NOTHING;
    REVOKE ALL ON public.databasechangelog_patients, public.databasechangeloglock_patients FROM PUBLIC;
    GRANT USAGE ON SCHEMA public TO patients_migrator;
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO patients_migrator, patients_runtime',current_database());
    IF EXISTS (SELECT FROM pg_namespace WHERE nspname='patients') THEN
        EXECUTE format('REVOKE CREATE ON DATABASE %I FROM patients_migrator',current_database());
    ELSE
        EXECUTE format('GRANT CREATE ON DATABASE %I TO patients_migrator',current_database());
    END IF;
END;
$$;
