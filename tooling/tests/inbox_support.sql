CREATE FUNCTION pg_temp.receive_assignment(received_id uuid, source_version integer DEFAULT 1)
RETURNS void LANGUAGE sql AS $$
INSERT INTO patients.inbox_events (event_id,aggregate_id,event_type,occurred_at,assignment_version,payload,correlation_id,causation_id)
VALUES (received_id,'90000000-0000-4000-8000-000000000001',
    'ClinicalAssignmentStarted','2026-01-01T00:00:00Z',source_version,
    '{"assignmentId":"90000000-0000-4000-8000-000000000001","patientId":"00000000-0000-4000-8000-000000000099",
      "dentistId":"10000000-0000-4000-8000-000000000001","startedAt":"2026-01-01T00:00:00Z",
      "startedBy":"10000000-0000-4000-8000-000000000001","version":1}'::jsonb || jsonb_build_object('version',source_version),
    '60000000-0000-4000-8000-000000000001','70000000-0000-4000-8000-000000000001');
$$;
