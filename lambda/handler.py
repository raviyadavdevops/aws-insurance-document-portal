import logging
import os
import urllib.parse

import boto3
import psycopg2

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

s3_client = boto3.client("s3")

DB_HOST = os.environ["DB_HOST"]
DB_PORT = os.environ.get("DB_PORT", "5432")
DB_NAME = os.environ["DB_NAME"]
DB_USER = os.environ["DB_USER"]
DB_PASSWORD = os.environ["DB_PASSWORD"]

CREATE_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS documents (
    id BIGSERIAL PRIMARY KEY,
    object_key TEXT UNIQUE NOT NULL,
    file_name TEXT NOT NULL,
    content_type TEXT NOT NULL,
    upload_timestamp TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
"""

UPSERT_SQL = """
INSERT INTO documents (object_key, file_name, content_type, upload_timestamp, updated_at)
VALUES (%(object_key)s, %(file_name)s, %(content_type)s, %(upload_timestamp)s, now())
ON CONFLICT (object_key) DO UPDATE SET
    file_name = EXCLUDED.file_name,
    content_type = EXCLUDED.content_type,
    upload_timestamp = EXCLUDED.upload_timestamp,
    updated_at = now();
"""


def get_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        connect_timeout=5,
    )


def process_record(record, conn):
    bucket = record["s3"]["bucket"]["name"]
    object_key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

    head = s3_client.head_object(Bucket=bucket, Key=object_key)
    content_type = head.get("ContentType", "application/octet-stream")
    upload_timestamp = head["LastModified"]
    file_name = object_key.rsplit("/", 1)[-1]

    with conn.cursor() as cur:
        cur.execute(
            UPSERT_SQL,
            {
                "object_key": object_key,
                "file_name": file_name,
                "content_type": content_type,
                "upload_timestamp": upload_timestamp,
            },
        )
    conn.commit()
    logger.info("success object_key=%s content_type=%s", object_key, content_type)


def handler(event, context):
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(CREATE_TABLE_SQL)
        conn.commit()

        for record in event.get("Records", []):
            object_key = "unknown"
            try:
                object_key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
                process_record(record, conn)
            except Exception as exc:  # noqa: BLE001 - must log every failure, never swallow it
                logger.error(
                    "failure object_key=%s error=%s", object_key, exc, exc_info=True
                )
                raise
    finally:
        conn.close()
