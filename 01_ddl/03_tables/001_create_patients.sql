CREATE TABLE patients.patients (
    patient_id uuid CONSTRAINT pk_patients PRIMARY KEY,
    document_type text NOT NULL,
    document_number text NOT NULL,
    name text NOT NULL,
    birth_date date NOT NULL,
    phone text NOT NULL,
    email text NOT NULL,
    address text,
    status text NOT NULL DEFAULT 'ACTIVE',
    version integer NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by uuid NOT NULL,
    updated_by uuid NOT NULL,
    CONSTRAINT ck_patients_document_type CHECK
        (char_length(document_type) BETWEEN 1 AND 30 AND document_type ~ '[^[:space:]]'),
    CONSTRAINT ck_patients_document_number CHECK
        (char_length(document_number) BETWEEN 1 AND 50 AND document_number ~ '[^[:space:]]'),
    CONSTRAINT ck_patients_name CHECK
        (char_length(name) BETWEEN 1 AND 255 AND name ~ '[^[:space:]]'),
    CONSTRAINT ck_patients_birth_date CHECK
        (isfinite(birth_date) AND birth_date < CURRENT_DATE),
    CONSTRAINT ck_patients_phone CHECK
        (char_length(phone) BETWEEN 1 AND 40 AND phone ~ '[^[:space:]]'),
    CONSTRAINT ck_patients_email CHECK
        (char_length(email) BETWEEN 1 AND 255 AND
         email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
    CONSTRAINT ck_patients_address CHECK
        (address IS NULL OR (char_length(address) BETWEEN 1 AND 500 AND address ~ '[^[:space:]]')),
    CONSTRAINT ck_patients_status CHECK (status IN ('ACTIVE', 'INACTIVE')),
    CONSTRAINT ck_patients_version CHECK (version > 0)
);
