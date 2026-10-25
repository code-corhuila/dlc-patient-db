CREATE TABLE patients.emergency_contacts (
    emergency_contact_id uuid CONSTRAINT pk_emergency_contacts PRIMARY KEY,
    patient_id uuid NOT NULL,
    name text NOT NULL,
    relationship text NOT NULL,
    phone text NOT NULL,
    CONSTRAINT ck_emergency_contacts_name CHECK
        (char_length(name) BETWEEN 1 AND 255 AND name ~ '[^[:space:]]'),
    CONSTRAINT ck_emergency_contacts_relationship CHECK
        (char_length(relationship) BETWEEN 1 AND 80 AND relationship ~ '[^[:space:]]'),
    CONSTRAINT ck_emergency_contacts_phone CHECK
        (char_length(phone) BETWEEN 1 AND 40 AND phone ~ '[^[:space:]]')
);
