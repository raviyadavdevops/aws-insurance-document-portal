# Contract: Flask Customer-Facing HTTP Endpoints

Base URL: the ALB's DNS name (HTTP, port 80) for the MVP.

## GET /

Renders the upload page.

- **Request**: no parameters.
- **Response**: `200 OK`, `text/html` — page containing a file-select input, an upload
  button, and a status area (initially empty).

## GET /health

Used by the ALB target group health check.

- **Request**: no parameters.
- **Response**:
  - `200 OK`, body `{"status": "ok"}` (or plain `OK`) when the process can serve traffic.
  - MUST NOT depend on S3/RDS reachability — this checks the Flask process itself, not
    downstream AWS services, so a transient S3 blip does not cause the ALB to cycle
    healthy instances (aligns with FR-005/Principle VI).

## POST /upload

Accepts a single file upload and stores it in S3.

- **Request**: `multipart/form-data` with one file field (e.g., `file`).
- **Success Response**: `200 OK`, `text/html` (or JSON `{"status": "success", "key": "<object_key>"}` — the AJAX/no-reload contract is an implementation choice for `/speckit-tasks`, not fixed here). Document is durably stored in S3 before this response is returned (FR-003, SC-002).
- **Error Responses** (all return a customer-safe message, never internal detail — ERR-001):
  - No file selected / empty payload → `400 Bad Request` (FR-017).
  - S3 write failure (e.g., transient AWS error) → `502 Bad Gateway` or `500 Internal
    Server Error`, generic "upload failed, please try again" message.
- **Explicitly NOT enforced** (per Clarifications): file size limit, file type
  allow-list. Any file/size the customer selects is accepted (FR-016).
- **Side effects**: None beyond the S3 write — `/upload` does NOT write to RDS directly
  and does NOT wait for Lambda/metadata processing to complete (FR-010, asynchronous by
  design).
