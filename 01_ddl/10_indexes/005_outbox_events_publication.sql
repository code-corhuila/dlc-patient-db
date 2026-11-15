CREATE INDEX idx_outbox_events_pending ON patients.outbox_events (next_retry_at,recorded_at,event_id) WHERE status='PENDING';
CREATE INDEX idx_outbox_events_aggregate_id ON patients.outbox_events (aggregate_id);
