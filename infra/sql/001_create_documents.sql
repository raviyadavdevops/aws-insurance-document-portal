-- Reference schema for the `documents` table (see data-model.md).
-- Applied automatically and idempotently by lambda/handler.py on every cold start
-- (CREATE TABLE IF NOT EXISTS) — no separate Terraform provisioner is needed since the
-- Lambda already has the required private network path to RDS that a local Terraform
-- run would not have.
CREATE TABLE IF NOT EXISTS documents (
    id BIGSERIAL PRIMARY KEY,
    object_key TEXT UNIQUE NOT NULL,
    file_name TEXT NOT NULL,
    content_type TEXT NOT NULL,
    upload_timestamp TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
