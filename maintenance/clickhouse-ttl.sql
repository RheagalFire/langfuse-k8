-- ClickHouse TTL Configuration for Langfuse
--
-- Apply these statements once against ClickHouse to enable automatic row expiry.
-- TTL is the proactive approach — rows are dropped during merges without external triggers.
-- The Lambda cleanup function is the reactive safety net (fires at 90% PVC usage).
--
-- Connect via: clickhouse-client --host <host> --port 9000 --password <password>
-- Or via HTTP: curl 'http://<host>:30123/?user=default&password=<password>' --data-binary @clickhouse-ttl.sql
--
-- IMPORTANT: Run each statement separately if using the HTTP interface.

-- ===========================================================================
-- Application tables — 30-day retention
-- ===========================================================================

ALTER TABLE default.observations
    MODIFY TTL created_at + INTERVAL 30 DAY;

ALTER TABLE default.traces
    MODIFY TTL timestamp + INTERVAL 30 DAY;

-- ===========================================================================
-- System logs — 10-day retention
-- ===========================================================================

ALTER TABLE system.opentelemetry_span_log
    MODIFY TTL start_time_us + INTERVAL 10 DAY;

ALTER TABLE system.query_log
    MODIFY TTL event_time + INTERVAL 10 DAY;

ALTER TABLE system.processors_profile_log
    MODIFY TTL event_time + INTERVAL 10 DAY;
