"""
Lambda function: langfuse-clickhouse-cleanup

Triggered by EventBridge when the ClickHouse PVC CloudWatch alarm fires (90% usage).
Connects to ClickHouse via NodePort and runs DELETE mutations to remove old data.

Retention defaults:
  - Application tables (observations, traces): 30 days
  - System logs (query_log, processors_profile_log, opentelemetry_span_log): 10 days

Environment variables:
  CLICKHOUSE_HOST     — ClickHouse endpoint (IP or DNS)
  CLICKHOUSE_PORT     — ClickHouse HTTP port (default: 30123)
  CLICKHOUSE_PASSWORD — ClickHouse password
  RETENTION_DAYS_APP  — Days to keep app data (default: 30)
  RETENTION_DAYS_SYSTEM — Days to keep system logs (default: 10)
"""

import os
import logging

import requests

logger = logging.getLogger()
logger.setLevel(logging.INFO)

CLICKHOUSE_HOST = os.environ.get("CLICKHOUSE_HOST", "127.0.0.1")
CLICKHOUSE_PORT = os.environ.get("CLICKHOUSE_PORT", "30123")
CLICKHOUSE_PASSWORD = os.environ["CLICKHOUSE_PASSWORD"]
RETENTION_DAYS_APP = int(os.environ.get("RETENTION_DAYS_APP", "30"))
RETENTION_DAYS_SYSTEM = int(os.environ.get("RETENTION_DAYS_SYSTEM", "10"))

CLICKHOUSE_URL = f"http://{CLICKHOUSE_HOST}:{CLICKHOUSE_PORT}"

# Queries: (database.table, retention_days, date_column)
CLEANUP_TARGETS = [
    ("default.observations", RETENTION_DAYS_APP, "created_at"),
    ("default.traces", RETENTION_DAYS_APP, "timestamp"),
    ("system.opentelemetry_span_log", RETENTION_DAYS_SYSTEM, "start_time_us"),
    ("system.query_log", RETENTION_DAYS_SYSTEM, "event_time"),
    ("system.processors_profile_log", RETENTION_DAYS_SYSTEM, "event_time"),
]


def run_query(query: str) -> str:
    """Execute a query against ClickHouse via HTTP interface."""
    response = requests.post(
        CLICKHOUSE_URL,
        params={"user": "default", "password": CLICKHOUSE_PASSWORD},
        data=query,
        timeout=120,
    )
    response.raise_for_status()
    return response.text.strip()


def lambda_handler(event, context):
    """Delete old rows from ClickHouse tables."""
    logger.info("Starting ClickHouse cleanup — host=%s:%s", CLICKHOUSE_HOST, CLICKHOUSE_PORT)
    logger.info("Retention: app=%d days, system=%d days", RETENTION_DAYS_APP, RETENTION_DAYS_SYSTEM)

    results = []
    for table, retention_days, date_col in CLEANUP_TARGETS:
        query = (
            f"ALTER TABLE {table} DELETE "
            f"WHERE {date_col} < now() - INTERVAL {retention_days} DAY"
        )
        logger.info("Running: %s", query)
        try:
            result = run_query(query)
            logger.info("OK — %s: %s", table, result or "(no output)")
            results.append({"table": table, "status": "ok", "result": result})
        except Exception as e:
            logger.error("FAILED — %s: %s", table, str(e))
            results.append({"table": table, "status": "error", "error": str(e)})

    logger.info("Cleanup complete: %s", results)
    return {"statusCode": 200, "results": results}
