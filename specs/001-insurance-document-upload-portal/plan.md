# Implementation Plan: AWS Cloud-Native Insurance Document Upload Portal

**Branch**: `001-insurance-document-upload-portal` | **Date**: 2026-09-27 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-insurance-document-upload-portal/spec.md`

## Summary

A customer uploads an insurance document through a minimal Flask web app running on EC2
behind an ALB/ASG. Flask writes the file directly to a private S3 bucket using the EC2
instance's IAM role — no credentials in code. S3 ObjectCreated fires a Python Lambda that
reads the object's key, content type, and last-modified time, and upserts a metadata row
(by object key) into a private RDS PostgreSQL `documents` table. Only Lambda has network
and IAM access to RDS; EC2 has none. Everything runs in one VPC across two AZs (public /
private-app / private-db subnet tiers), with no NAT Gateway and no file-size/type
validation in the MVP (both are documented, deliberate scope cuts). All infrastructure is
Terraform; the whole thing must `terraform apply` and `terraform destroy` cleanly.

## Technical Context

**Language/Version**: Python 3.12 for the Flask application (EC2); Python 3.11 for the
Lambda function (pinned for `psycopg2-binary` manylinux wheel compatibility with the
Lambda Layer build in `infra/lambda_layer.tf` — see research.md).

**Primary Dependencies**: Flask, boto3 (AWS SDK, present by default in the Lambda runtime;
installed explicitly for the EC2-side Flask app), psycopg2-binary (Lambda → PostgreSQL),
gunicorn (production WSGI server for Flask on EC2).

**Storage**: Amazon S3 (document bytes) + Amazon RDS PostgreSQL (`documents` metadata
table).

**Testing**: pytest for Flask route unit/integration tests (using moto or a local stub for
S3) and for Lambda handler unit tests (mocked S3 event + mocked psycopg2 connection).

**Target Platform**: AWS — EC2 (Amazon Linux 2023) behind ALB/ASG; AWS Lambda (Python
3.12 managed runtime).

**Project Type**: Web application (customer-facing Flask app) + event-driven backend
(Lambda) + infrastructure (Terraform). Treated as a single repository with three source
areas: `app/`, `lambda/`, `infra/`.

**Performance Goals**: Upload-to-success-confirmation under 30s for a typical (<5MB)
file on broadband (SC-001); metadata record created within 60s for ≥99% of uploads
(SC-003/NFR-003).

**Constraints**: No NAT Gateway (cost — Principle V/XI); no Multi-AZ RDS (cost — Principle
XI); no file-size/type enforcement in MVP (per Clarifications); EC2 has zero network/IAM
path to RDS (Principle IV/V); only Lambda may reach PostgreSQL.

**Scale/Scope**: Demonstration-scale MVP — documented baseline of ~50 concurrent uploads
(NFR-002), single ASG spanning 2 AZs, single-instance RDS (no read replica/standby).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Status |
|---|---|---|
| I. Cloud-Native AWS Architecture | ALB/ASG/EC2, S3, Lambda, RDS all AWS-managed; single VPC, 2 AZs | PASS |
| II. Infrastructure as Code | All infra in Terraform (`infra/`); no manual console steps planned | PASS |
| III. Security by Default | S3 Block Public Access + SSE enabled; RDS `publicly_accessible=false`; no hard-coded secrets (IAM roles only) | PASS |
| IV. Least-Privilege Access | Distinct EC2 instance role (S3 read/write only) and Lambda execution role (S3 read + RDS connect + logs only); no wildcard policies planned | PASS |
| V. Network Isolation | 2 public / 2 private-app / 2 private-db subnets; RDS reachable only from Lambda SG; EC2 has no DB route; S3 Gateway VPC Endpoint for EC2; no NAT Gateway (documented trade-off) | PASS |
| VI. High Availability and Scalability | ALB + ASG across 2 AZs; target group health check on `/health` | PASS |
| VII. Asynchronous Document Processing | S3 ObjectCreated → Lambda → RDS upsert; failures logged, not swallowed | PASS |
| VIII. Application Simplicity | Flask only; exactly `/`, `/health`, `/upload`; plain HTML/CSS | PASS |
| IX. Lambda Simplicity | Lambda does only metadata extraction + upsert; logs to CloudWatch | PASS |
| X. Observability | CloudWatch logs from Flask (via journald/CloudWatch agent or app-level logging) and Lambda (native); dashboards/alarms optional and out of MVP scope | PASS |
| XI. Cost Awareness | No NAT Gateway, no Multi-AZ RDS, single RDS instance — all explicit | PASS |
| XII. Reproducibility and Documentation | README to cover prereqs/deploy/validate/demo/cleanup; repo holds app+lambda+infra+deps+docs | PASS (to be authored during implementation) |
| XIII. Scope Discipline | No file validation, no auth, no NAT — each an explicit, documented cut, not silent omission | PASS |
| XIV. Definition of Done | All sub-items map directly to User Stories 1–3 and FR/SEC requirements in spec.md | PASS |

No violations requiring justification. Complexity Tracking table is not needed.

## Project Structure

### Documentation (this feature)

```text
specs/001-insurance-document-upload-portal/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
app/                      # Flask customer-facing web application
├── app.py                 # Routes: GET /, GET /health, POST /upload
├── requirements.txt
├── templates/
│   └── index.html          # Simple upload form (file input + submit + status)
└── static/
    └── style.css           # Minimal CSS

lambda/                    # S3-triggered metadata-processing function
├── handler.py              # Lambda entry point: parse S3 event, extract metadata, upsert to RDS
└── requirements.txt        # psycopg2-binary (bundled into deployment package/layer)

infra/                      # Terraform, organized by concern
├── main.tf
├── variables.tf
├── outputs.tf
├── vpc.tf                  # VPC, 2 AZs, 6 subnets (public/app/db x2), route tables, S3 Gateway Endpoint
├── security_groups.tf      # ALB, EC2, Lambda, RDS security groups
├── alb.tf                  # ALB, target group (/health), listener
├── asg.tf                  # Launch template, Auto Scaling Group, EC2 IAM role/instance profile
├── s3.tf                   # Document bucket (private, encrypted, Block Public Access), event notification
├── lambda.tf                # Lambda function, execution role, S3 trigger permission
├── rds.tf                   # DB subnet group, RDS PostgreSQL instance, parameter group
└── terraform.tfvars.example

tests/
├── app/                     # pytest for Flask routes
└── lambda/                  # pytest for Lambda handler

README.md                   # Prereqs, deploy, validate, demo, cleanup instructions
```

**Structure Decision**: Single repository, three sibling top-level source areas
(`app/`, `lambda/`, `infra/`) plus `tests/` mirroring `app/` and `lambda/`. This is not the
generic "web application" frontend/backend split (there is no separate API backend — Flask
serves the UI directly and writes straight to S3), and not a bare single-project layout
either (Lambda and Terraform are independently deployable units). The three-area layout
directly matches Constitution Principle XII's required deliverable: application code,
Lambda code, and infrastructure as clearly separated, independently reviewable pieces.

## Complexity Tracking

> No Constitution Check violations — this section is intentionally empty.
