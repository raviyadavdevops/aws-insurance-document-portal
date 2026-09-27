# Phase 1 Data Model: AWS Cloud-Native Insurance Document Upload Portal

## Entity: Document (S3 object)

Not a database row — represented by an object in the private S3 bucket.

| Attribute | Type | Notes |
|---|---|---|
| object_key | string | S3 key; unique within the bucket. Used as the natural join key to the metadata record. |
| content_type | string | As declared by the uploading client / set on `put_object`. |
| size_bytes | integer | Not size-limited in MVP (per Clarifications) — recorded for reference only, not required in the metadata table. |
| uploaded_at | timestamp | S3 object creation time. |

Validation rules: none enforced (no size cap, no content-type allow-list) — explicit MVP
scope cut per spec Clarifications/Assumptions. Only requirement: object key must be
non-empty and the payload must be non-empty (FR-017).

## Entity: Document Metadata Record (`documents` table, RDS PostgreSQL)

| Column | Type | Constraints | Notes |
|---|---|---|---|
| id | BIGSERIAL / UUID | PRIMARY KEY | Internal surrogate key. |
| object_key | TEXT | UNIQUE NOT NULL | The upsert key (FR-009); corresponds 1:1 with the S3 object. |
| file_name | TEXT | NOT NULL | Derived from the object key (basename), satisfies spec's "file name" field. |
| content_type | TEXT | NOT NULL | From S3 `head_object` `ContentType`. |
| upload_timestamp | TIMESTAMPTZ | NOT NULL | From S3 object's `LastModified`. |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT now() | First-insert bookkeeping (not in spec's minimum set, but useful and harmless). |
| updated_at | TIMESTAMPTZ | NOT NULL DEFAULT now() | Bumped on every upsert — supports observing reprocessing (FR-009 upsert behavior). |

Lifecycle: A row is created on first successful processing of an `object_key` and updated
in place (same row, `updated_at` bumped) on any subsequent processing of the same key —
no delete path in MVP scope.

Relationships: One `documents` row corresponds to exactly one S3 object (`object_key` is
unique). No other entities in this MVP.

## Entity: Processing Log Entry (CloudWatch Logs — not a database table)

| Field | Notes |
|---|---|
| object_key | Which document the log line concerns. |
| outcome | `success` or `failure`. |
| timestamp | Implicit CloudWatch log timestamp. |
| error_detail | Present only on failure; exception type/message, not a stack trace dump to the customer (that stays server-side in CloudWatch, per ERR-001/ERR-003). |

This is not a persisted application entity — it exists purely as structured log lines
emitted by the Lambda handler (and, for application-level errors, by Flask), satisfying
FR-011/FR-012 and Success Criterion SC-006 without adding a new datastore.
