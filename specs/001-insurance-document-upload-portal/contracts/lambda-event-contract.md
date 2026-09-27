# Contract: S3 → Lambda Event Trigger and RDS Write

## Trigger

- **Event source**: S3 bucket notification, event type `s3:ObjectCreated:*`, scoped to
  the document bucket (no prefix/suffix filter needed for MVP — every object triggers
  processing).
- **Invocation**: Lambda is invoked asynchronously by S3; at-least-once delivery is
  assumed (S3/Lambda's standard guarantee) — the handler MUST be idempotent (see below).

## Input (per S3 event record)

- `Records[].s3.bucket.name`
- `Records[].s3.object.key` (URL-encoded; handler MUST decode before use)

The handler additionally calls S3 `head_object(Bucket, Key)` to retrieve authoritative
`ContentType` and `LastModified`, since the event payload's own metadata is not
guaranteed sufficient (see research.md §3).

## Output / Side Effect

- One row upserted into the `documents` table (see data-model.md), keyed on
  `object_key`:
  - On first processing of a key: INSERT.
  - On any later reprocessing of the same key (retry, redelivery): UPDATE in place
    (`updated_at` bumped) — no duplicate row (FR-009, per Clarifications).
- One CloudWatch log line per invocation reporting outcome:
  - Success: object key, content type, timestamp, and "success".
  - Failure: object key, "failure", and error detail (exception type/message) — MUST NOT
    be silently dropped (FR-011/FR-012, ERR-003).

## Failure Handling

- Transient failures (e.g., RDS connection timeout) should raise so Lambda's built-in
  retry applies; the resulting retry naturally exercises the upsert idempotency path
  above.
- Non-retryable failures (e.g., malformed/missing object) are logged with enough detail
  to identify the object and are not retried indefinitely.
- A metadata-processing failure is NEVER surfaced to the customer — the customer's
  upload already succeeded once Flask's `/upload` returned 200 (ERR-002).
