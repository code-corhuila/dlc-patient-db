CREATE UNIQUE INDEX uk_patients_document ON patients.patients
    (upper(btrim(document_type)), upper(btrim(document_number)));
