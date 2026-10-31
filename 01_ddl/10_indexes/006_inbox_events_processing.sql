CREATE UNIQUE INDEX uk_inbox_events_source ON patients.inbox_events (producer,aggregate_id,event_type,assignment_version);
CREATE INDEX ix_inbox_events_pending ON patients.inbox_events (next_retry_at,recorded_at,event_id) WHERE status='PENDING';
