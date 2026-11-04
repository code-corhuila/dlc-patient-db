DO $$
DECLARE offender text;
BEGIN
    SELECT string_agg(c.relname,', ') INTO offender FROM pg_class c
    WHERE c.relnamespace='patients'::regnamespace AND c.relkind='r' AND c.relname !~ '^[a-z]+(_[a-z]+)*$';
    IF offender IS NOT NULL THEN RAISE EXCEPTION 'tables must be snake_case: %',offender; END IF;
    SELECT string_agg(c.relname,', ') INTO offender FROM pg_class c
    WHERE c.relnamespace='patients'::regnamespace AND c.relkind='r' AND c.relname ~ 's$';
    IF offender IS NOT NULL THEN RAISE EXCEPTION 'tables must be singular: %',offender; END IF;
    SELECT string_agg(conname,', ') INTO offender FROM pg_constraint
    WHERE connamespace='patients'::regnamespace AND conname !~ '^(pk|fk|chk)_';
    IF offender IS NOT NULL THEN RAISE EXCEPTION 'constraints must use pk_, fk_ or chk_: %',offender; END IF;
    SELECT string_agg(i.indexname,', ') INTO offender FROM pg_indexes i
    WHERE i.schemaname='patients' AND i.indexname !~ '^(pk|idx|uk)_';
    IF offender IS NOT NULL THEN RAISE EXCEPTION 'indexes must use idx_ or uk_: %',offender; END IF;
END;
$$;
