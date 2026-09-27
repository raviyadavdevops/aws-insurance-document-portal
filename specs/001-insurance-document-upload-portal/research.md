# Phase 0 Research: AWS Cloud-Native Insurance Document Upload Portal

No open `NEEDS CLARIFICATION` markers remain in the Technical Context — the feature
description and constitution were specific enough to fix every technology choice.
This document records the resulting decisions and their rationale for traceability.

## 1. Flask deployment on EC2

- **Decision**: Run Flask under gunicorn as a systemd service on Amazon Linux 2023,
  launched via the ASG launch template's user-data script.
- **Rationale**: gunicorn is the standard production WSGI server for Flask; systemd
  gives automatic restart on crash, which matters since the ALB health check depends on
  the process staying up. Avoids introducing a container/orchestration layer the
  constitution explicitly says to avoid (Principle VIII: no unnecessary complexity).
- **Alternatives considered**: Flask dev server (rejected — not production-safe, single
  threaded, explicitly warned against by Flask itself); ECS/Fargate (rejected — the
  constitution mandates EC2 + ASG for this MVP, and a container platform would add
  operational surface area disproportionate to the assignment).

## 2. EC2-to-S3 upload path

- **Decision**: Flask uses `boto3` with the default credential chain (which resolves to
  the EC2 instance profile's temporary credentials) to call `put_object` directly against
  the private bucket, routed over the S3 Gateway VPC Endpoint.
- **Rationale**: Satisfies "no hard-coded credentials" (Principle III) and "EC2 must use
  an IAM instance role" (Principle IV) with zero extra code — boto3's default chain finds
  instance-profile credentials automatically. The Gateway Endpoint keeps this traffic off
  the public internet without needing a NAT Gateway.
- **Alternatives considered**: Presigned URLs from a separate signer (rejected —
  unnecessary indirection for this MVP; Flask already runs with a role that can write
  directly); static IAM user access keys (rejected — explicitly forbidden by Principle
  III).

## 3. Lambda trigger and metadata extraction

- **Decision**: S3 bucket notification configuration invokes the Lambda function
  directly on `s3:ObjectCreated:*`. The handler reads `event['Records'][n]['s3']` for
  bucket/key, then calls `head_object` (or uses the event's own size/eTag plus a
  `head_object` for `ContentType`) to get `ContentType`, and uses `LastModified` from that
  call as the upload timestamp.
- **Rationale**: Direct S3→Lambda notification is the simplest reliable async trigger
  path (Principle VII) and needs no intermediate queue for MVP scale. `head_object` is
  necessary because the S3 event payload itself does not reliably include
  `Content-Type`.
- **Alternatives considered**: Routing through SNS/SQS before Lambda (rejected as
  unneeded complexity for this MVP's throughput — Principle IX/XIII); parsing content
  type from the file extension client-side (rejected — less reliable than the object's
  actual stored `Content-Type`, and moves logic into the simple Flask app unnecessarily).

## 4. Lambda-to-RDS connectivity and idempotency

- **Decision**: Lambda runs inside the private application (or a dedicated Lambda) subnet
  with a security group that is the only one permitted to reach RDS's security group on
  port 5432. Lambda uses `psycopg2` to run `INSERT ... ON CONFLICT (object_key) DO UPDATE`
  against the `documents` table.
- **Rationale**: Matches Principle V (only Lambda talks to Postgres) and the clarified
  requirement that redelivered/duplicate S3 events upsert rather than duplicate a record.
  `ON CONFLICT DO UPDATE` is the native PostgreSQL idiom for this and needs no
  application-level "check then insert" race-prone logic.
- **Alternatives considered**: Select-then-insert-or-update in application code
  (rejected — race-prone under concurrent/duplicate Lambda invocations); a dedicated RDS
  Proxy (rejected — adds cost/complexity not justified at this MVP's connection volume).

## 5. Observability approach

- **Decision**: Lambda relies on default CloudWatch Logs (via the Lambda execution role's
  standard logging permissions) with structured, single-line log messages per invocation
  (`object_key`, outcome, and — on failure — exception detail). Flask logs to stdout/
  stderr, which the CloudWatch agent (or systemd → CloudWatch Logs) ships to a log group.
- **Rationale**: Satisfies Principle X (observable via CloudWatch, enough detail to
  troubleshoot) without requiring dashboards/alarms, which the constitution marks
  optional for the MVP.
- **Alternatives considered**: AWS X-Ray tracing (rejected — valuable but not required by
  the constitution or spec; adds setup overhead disproportionate to MVP scope).

## 6. Terraform module layout

- **Decision**: Flat `infra/` root module (no nested modules) with resources grouped into
  files by concern (`vpc.tf`, `security_groups.tf`, `alb.tf`, `asg.tf`, `s3.tf`,
  `lambda.tf`, `rds.tf`), driven by `variables.tf`/`terraform.tfvars`.
- **Rationale**: A flat root module is easiest for a reviewer to read end-to-end and
  matches Principle XIII ("Terraform implementation details should not unnecessarily
  constrain functional requirements" — i.e., don't over-engineer module abstraction for a
  single-environment MVP).
- **Alternatives considered**: Reusable child modules per tier (rejected — premature
  abstraction for a single-deployment MVP with no second environment to reuse it for).
