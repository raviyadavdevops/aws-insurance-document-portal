---

description: "Task list for AWS Cloud-Native Insurance Document Upload Portal"
---

# Tasks: AWS Cloud-Native Insurance Document Upload Portal

**Input**: Design documents from `/specs/001-insurance-document-upload-portal/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Not explicitly requested in the feature specification; test tasks are omitted.
Manual validation is covered by `quickstart.md`.

**Organization**: Tasks are grouped by user story (P1/P2/P3 from spec.md) to enable
independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (upload), US2 (metadata processing), US3 (availability/privacy/observability)

## Path Conventions

Per plan.md's Project Structure: `app/` (Flask), `lambda/` (metadata processor), `infra/`
(Terraform), repository root for `README.md`.

---

## Phase 1: Setup (project initialization)

- [X] T001 Create repository skeleton directories: `app/templates/`, `app/static/`,
  `lambda/`, `infra/`, per plan.md's Project Structure
- [X] T002 [P] Create `app/requirements.txt` with `Flask`, `boto3`, `gunicorn` pinned to
  specific versions
- [X] T003 [P] Create `lambda/requirements.txt` with `psycopg2-binary` pinned to a
  specific version
- [X] T004 [P] Create `infra/terraform.tfvars.example` documenting required input
  variables (region, project name, DB credentials variable names, bucket name prefix)
- [X] T005 [P] Create root `README.md` skeleton with sections: Prerequisites, Deployment,
  Validation, Demonstration, Assumptions & Limitations, Cleanup (content filled
  incrementally in later tasks per Constitution Principle XII)

**Checkpoint**: Repository layout exists; dependency manifests are in place.

---

## Phase 2: Foundational (blocking prerequisites for all user stories)

**Purpose**: Core network/security infrastructure that every user story's Terraform
resources depend on. No user story can be deployed/tested until this phase completes.

- [X] T006 Define `infra/variables.tf` with inputs for region, AZ list (exactly 2 AZs per
  Constitution Principle I/V), project/name prefix, and DB master username/password
  variable placeholders (marked `sensitive = true`, no defaults — Constitution
  Principle III: no hard-coded secrets)
- [X] T007 Implement VPC, 2 public subnets, 2 private application subnets, and 2 private
  database subnets across 2 AZs in `infra/vpc.tf`, per data-model.md's network tiers and
  spec.md's Network Isolation requirements (SEC-004)
- [X] T008 Add route tables in `infra/vpc.tf`: public subnets route to an Internet
  Gateway; private application and private database subnets have NO route to a NAT
  Gateway or Internet Gateway (Constitution Principle V — NAT Gateway intentionally
  omitted)
- [X] T009 [P] Add an S3 Gateway VPC Endpoint in `infra/vpc.tf`, associated with the
  private application subnets' route tables, for private EC2-to-S3 access (spec.md
  Network Isolation requirement)
- [X] T010 Define four security groups in `infra/security_groups.tf`: `alb_sg` (ingress
  80/tcp from 0.0.0.0/0), `ec2_sg` (ingress from `alb_sg` only, on the app port), `lambda_sg`
  (no ingress; egress needed for RDS + S3 API + CloudWatch Logs), `rds_sg` (ingress 5432/tcp
  from `lambda_sg` only) — matching spec.md SEC-004/SEC-005 exactly (EC2 has NO path to
  `rds_sg`)
- [X] T011 Define `infra/outputs.tf` exposing ALB DNS name, S3 bucket name, RDS endpoint,
  and Lambda function name (needed for quickstart.md's validation commands)

**Checkpoint**: Network and security-group skeleton exists; no compute/storage resources
yet. All user story phases below build on this.

---

## Phase 3: User Story 1 - Customer uploads an insurance document (Priority: P1) 🎯 MVP

**Goal**: A customer can open the portal via the ALB, select a file, upload it, and see a
success or error status; the file lands in a private S3 bucket.

**Independent Test**: Deploy through this phase, open the ALB URL, upload a file via the
browser, confirm a success message appears and the object exists in S3 (quickstart.md
steps 1–3).

### Implementation for User Story 1

- [X] T012 [P] [US1] Implement `GET /` route rendering `app/templates/index.html` (file
  input + upload button + empty status area) in `app/app.py`, per
  contracts/flask-http-api.md
- [X] T013 [P] [US1] Implement `GET /health` route in `app/app.py` returning `200 OK`
  with a static body, with NO dependency on S3/RDS reachability, per
  contracts/flask-http-api.md
- [X] T014 [US1] Implement `POST /upload` route in `app/app.py`: validate a file was
  selected and the payload is non-empty (return `400` with a plain-language error if not
  — FR-017); otherwise use `boto3` (default credential chain, resolving to the EC2
  instance role — no hard-coded credentials, FR-021) to `put_object` the file into the S3
  bucket; return a success response once the S3 write confirms (FR-003); on any S3/AWS
  error, return a generic customer-safe error message without internal detail (ERR-001)
- [X] T015 [US1] Explicitly do NOT enforce any file-size or file-content-type
  restriction in the `/upload` handler in `app/app.py` — per FR-016 (clarified: any file
  size/type is accepted in the MVP); add a one-line comment noting this is a deliberate,
  documented scope cut, not an oversight
- [X] T016 [P] [US1] Add minimal styling in `app/static/style.css` for the upload page
  (Constitution Principle VIII: intentionally simple UI)
- [X] T017 [US1] Wire success/error status display into `app/templates/index.html` (e.g.,
  a status `<div>` populated via a simple form POST redirect-with-message or minimal
  inline JS/fetch — implementer's choice, no framework)
- [X] T018 [US1] Provision the private S3 bucket in `infra/s3.tf`: enable S3 Block Public
  Access (all four settings true), enable default server-side encryption (SSE-S3 or
  SSE-KMS), and do NOT attach a public bucket policy (SEC-001, SEC-002, SEC-008)
- [X] T019 [US1] Define the EC2 IAM role and instance profile in `infra/asg.tf` (or a
  dedicated `infra/iam.tf`) granting least-privilege S3 access scoped per-prefix: `s3:PutObject`
  on `${bucket.arn}/uploads/*` (customer uploads) and `s3:GetObject` on
  `${bucket.arn}/app-artifacts/*` (its own deployment artifact only) — no wildcard
  resource, no ability to read other customers' uploaded documents, no other AWS service
  permissions (FR-021, Constitution Principle IV; tightened per analyze finding M4)
- [X] T020 [US1] Define the launch template in `infra/asg.tf`: Amazon Linux 2023 AMI,
  attaches the EC2 instance profile from T019, places instances in the private
  application subnets from T007, attaches `ec2_sg` from T010, and runs user-data that
  installs Python, installs `app/requirements.txt`, and starts Flask under `gunicorn` via
  systemd (research.md §1)
- [X] T020a [US1] Package `app/` (code, templates, static, requirements.txt) via
  `archive_file` and upload it to `s3://<bucket>/app-artifacts/app_package.zip` in
  `infra/app_deploy.tf`; update the launch template's user-data in `infra/asg.tf` to
  download and unpack this artifact and install its dependencies on every boot, starting
  `flask-app.service` only after those steps succeed — ensures every new/replacement ASG
  instance runs the current app code without CodeDeploy (remediates analyze finding M1)
- [X] T021 [US1] Define the Auto Scaling Group in `infra/asg.tf` spanning both private
  application subnets (2 AZs), with a minimum of 2 and desired capacity of 2 instances
  (Constitution Principle VI: capacity spans 2 AZs)
- [X] T022 [US1] Define the ALB, target group (health check path `/health`), and HTTP
  listener (port 80) in `infra/alb.tf`; ALB placed in the public subnets from T007 with
  `alb_sg` from T010; target group registers the ASG from T021
  (contracts/flask-http-api.md's `/health` contract, Constitution Principle VI)

**Checkpoint**: User Story 1 is independently deployable and testable — a customer can
upload a document and see it land in S3, entirely without Lambda/RDS existing yet.

---

## Phase 4: User Story 2 - Document metadata is automatically extracted and recorded (Priority: P2)

**Goal**: Once a document is stored (via US1 or by placing an object directly in S3), its
metadata is automatically extracted and upserted into a private RDS PostgreSQL
`documents` table, with every attempt logged.

**Independent Test**: With US1's S3 bucket in place, upload/PUT an object, then query
`documents` in RDS to confirm a record was created with correct `file_name`,
`content_type`, and `upload_timestamp` within 60 seconds; re-upload the same key and
confirm the same row is updated, not duplicated (quickstart.md step 4).

### Implementation for User Story 2

- [X] T023 [P] [US2] Implement `lambda/handler.py`: parse the S3 event's
  `Records[].s3.bucket.name`/`object.key` (URL-decoding the key), per
  contracts/lambda-event-contract.md
- [X] T024 [US2] In `lambda/handler.py`, call S3 `head_object` to retrieve `ContentType`
  and `LastModified` for the object (research.md §3); derive `file_name` as the object
  key's basename
- [X] T025 [US2] In `lambda/handler.py`, connect to RDS PostgreSQL via `psycopg2` (using
  connection details from environment variables set by Terraform — no hard-coded
  credentials, FR-021/SEC-007) and execute an `INSERT ... ON CONFLICT (object_key) DO
  UPDATE` against the `documents` table, per data-model.md's schema, setting `object_key`
  (UNIQUE NOT NULL), `file_name`, `content_type`, `upload_timestamp`, and bumping
  `updated_at` on conflict
- [X] T026 [US2] In `lambda/handler.py`, log one structured line per invocation to
  CloudWatch: on success, `object_key` + content type + "success"; on failure,
  `object_key` + "failure" + exception detail — never silently swallow an exception
  (FR-011, FR-012, ERR-003); re-raise transient errors so Lambda's built-in retry applies
  (contracts/lambda-event-contract.md's Failure Handling)
- [X] T027 [US2] Create the `documents` table schema (via a SQL migration file
  `infra/sql/001_create_documents.sql` or an init step referenced from `infra/rds.tf`)
  exactly matching data-model.md: `id` (surrogate PK), `object_key` (UNIQUE NOT NULL),
  `file_name` (NOT NULL), `content_type` (NOT NULL), `upload_timestamp` (TIMESTAMPTZ NOT
  NULL), `created_at`/`updated_at` (TIMESTAMPTZ NOT NULL DEFAULT now())
- [X] T028 [US2] Provision the RDS PostgreSQL instance in `infra/rds.tf`: DB subnet group
  covering the two private database subnets from T007, `publicly_accessible = false`,
  single instance (no Multi-AZ, Constitution Principle XI), security group `rds_sg` from
  T010, master credentials sourced from Terraform variables (never literals, SEC-007)
- [X] T029 [US2] Define the Lambda execution role in `infra/lambda.tf`: least-privilege
  permissions for `s3:GetObject` scoped to the document bucket ARN, CloudWatch Logs write
  permissions, and VPC-execution permissions (ENI create/describe) — no RDS IAM
  permission needed since access is via network/security-group + DB credentials, not IAM
  auth (Constitution Principle IV)
- [X] T030 [US2] Define the Lambda function resource in `infra/lambda.tf`: Python 3.11
  runtime (updated from 3.12 for psycopg2-binary manylinux wheel compatibility), deployment
  package built from `lambda/handler.py`, placed in the private application subnets (T007)
  with `lambda_sg` from T010, environment variables for the RDS endpoint/db name
  (credentials via a securely injected variable, not plaintext in the function definition)
- [X] T030a [US2] Build the `psycopg2-binary` dependency as a Lambda Layer in
  `infra/lambda_layer.tf`: a `null_resource` `local-exec` runs `pip install ...
  --platform manylinux2014_x86_64 --python-version 3.11 --only-binary=:all:` (triggered
  on `lambda/requirements.txt`'s hash), zipped via `archive_file`, published as
  `aws_lambda_layer_version`, and attached to the function from T030 via `layers = [...]`
  — remediates analyze finding C1 (Lambda previously could not import psycopg2)
- [X] T030b [US2] Harden `infra/lambda_layer.tf`'s `local-exec` provisioner: run it via
  explicit `interpreter = ["bash", "-c"]` with a single-line command (no shell
  continuation), so it behaves identically under Windows/macOS/Linux instead of falling
  back to `cmd.exe` on Windows; track `infra/build/layer/python/.gitkeep` so
  `data.archive_file.lambda_layer`'s `source_dir` exists at `terraform plan` time on a
  clean checkout — remediates analyze findings C2 and C3
- [X] T031 [US2] Configure the S3 bucket notification on the bucket from T018 in
  `infra/s3.tf` to invoke the Lambda function from T030 on `s3:ObjectCreated:*`, including
  the required `aws_lambda_permission` resource granting S3 invoke rights
  (contracts/lambda-event-contract.md's Trigger section)

**Checkpoint**: User Story 2 is independently testable on top of US1 — uploads now
produce metadata rows, with idempotent upserts and full failure logging.

---

## Phase 5: User Story 3 - System remains available and private under normal operation (Priority: P3)

**Goal**: Confirm/harden availability (auto-scaling, health-check replacement) and
privacy (no public access to S3/RDS) end to end, and ensure operators can find
enough detail in logs to diagnose issues.

**Independent Test**: Attempt direct public access to the S3 bucket and RDS instance and
confirm both are refused; stop the app process on one EC2 instance and confirm the ALB
detects it unhealthy and the ASG replaces it without customer-visible downtime; inspect
CloudWatch logs for both a successful and a deliberately-failed processing attempt
(quickstart.md steps 5–7).

### Implementation for User Story 3

- [X] T032 [P] [US3] Configure the ALB target group health check in `infra/alb.tf` with
  explicit thresholds (e.g., healthy threshold 2, unhealthy threshold 2–3, interval 15–30s)
  against `/health`, so an unhealthy instance is detected and replaced automatically
  (FR-019, Constitution Principle VI)
- [X] T033 [P] [US3] Add an Auto Scaling policy (target-tracking on CPU utilization, or a
  documented step policy) to the ASG in `infra/asg.tf` so capacity increases under load
  and decreases as demand falls (FR-020, NFR-002)
- [X] T034 [P] [US3] Verify and, if needed, tighten the S3 bucket policy in `infra/s3.tf`
  to explicitly deny any `s3:*` action when the request is not via the VPC endpoint or the
  EC2/Lambda roles — belt-and-suspenders on top of Block Public Access (SEC-001, SEC-008)
- [X] T035 [P] [US3] Add CloudWatch Logs configuration for the Flask application (install
  and configure the CloudWatch agent, or route journald output, in the launch template
  user-data from T020) so application-level errors are retrievable by an operator
  (NFR-005)
- [X] T036 [US3] Add a "Useful CloudWatch Metrics & Logs" section to `README.md`
  documenting, per component, what to watch: ALB (`HealthyHostCount`,
  `UnHealthyHostCount`, `HTTPCode_Target_5XX_Count`), EC2/ASG (`CPUUtilization`,
  `GroupInServiceInstances`), Lambda (`Errors`, `Duration`, `Invocations`), RDS
  (`DatabaseConnections`, `FreeStorageSpace`), S3 (request metrics) — satisfies
  Constitution Principle X's "important metrics should be documented" without requiring
  dashboards/alarms
- [ ] T037 [US3] Manually verify (and record the result in README.md's Validation
  section) that direct anonymous access to the S3 bucket and to the RDS instance's
  network endpoint both fail, per quickstart.md step 6 (SC-004)

**Checkpoint**: All three user stories are independently deployable, testable, and
demonstrable; the system meets availability, privacy, and observability expectations.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final documentation, reproducibility, and Definition-of-Done closure —
touches all stories but adds no new functional behavior.

- [X] T038 [P] Fill in `README.md`'s Prerequisites and Deployment sections with exact
  `terraform init`/`terraform apply` steps and required variables (Constitution
  Principle XII)
- [X] T039 [P] Fill in `README.md`'s Validation and Demonstration sections by adapting
  quickstart.md's 8 steps into copy-pasteable commands with the actual output values from
  `infra/outputs.tf` (T011)
- [X] T040 [P] Add a "Production Enhancements" section to `README.md` explicitly listing
  deferred items: NAT Gateway, Multi-AZ RDS, file-size/type validation, customer
  authentication, dashboards/alarms — each with a one-line rationale for why it's out of
  MVP scope (Constitution Principle XIII)
- [X] T041 [P] Fill in `README.md`'s Cleanup section with `terraform destroy` steps and a
  post-destroy verification checklist (Constitution Principle XII, quickstart.md step 8)
- [ ] T042 Run through quickstart.md end-to-end against a real deployment and record any
  deviations/fixes needed in `README.md`'s Assumptions & Limitations section

---

## Dependencies & Execution Order

- **Phase 1 (Setup)** → **Phase 2 (Foundational)** → user story phases (3, 4, 5) →
  **Phase 6 (Polish)**.
- **User Story 1 (Phase 3)** has no dependency on US2/US3 and is independently
  deployable/testable once Phase 2 completes — this is the MVP.
- **User Story 2 (Phase 4)** depends on the S3 bucket existing (T018, from US1) but not on
  the ALB/ASG/Flask app itself — it can be built and tested by dropping objects directly
  into S3 even before US1's UI is finished, though in practice US1 is expected to precede
  it.
- **User Story 3 (Phase 5)** depends on US1's ALB/ASG (T020–T022) and, for log-review
  tasks, on US2's Lambda (T030) — build it last.
- Within each phase, tasks marked **[P]** touch different files and can run in parallel;
  unmarked tasks within a phase have an implied order (e.g., T024 needs T023's parsed
  event; T031 needs both T018's bucket and T030's function to exist).

## Parallel Execution Examples

- **Phase 1**: T002, T003, T004, T005 can all run in parallel (independent files).
- **Phase 3 (US1)**: T012, T013, T016 can run in parallel (independent files); T018,
  T019 can run in parallel with each other and with T012–T017 (Terraform vs. app code).
- **Phase 4 (US2)**: T023 alone first; then T027, T028, T029 can run in parallel
  (independent Terraform files) while T024–T026 are written against the (parallel-built)
  handler skeleton.
- **Phase 5 (US3)**: T032, T033, T034, T035 can all run in parallel (independent
  Terraform/config changes).
- **Phase 6**: T038, T039, T040, T041 can all run in parallel (independent README
  sections); T042 runs last, after all others.

## Implementation Strategy

**MVP first**: Complete Phase 1 → Phase 2 → Phase 3 (US1) and stop there for a first
demonstrable increment — a customer can upload a document to private S3 through a
highly-available ALB/ASG, even before metadata processing exists.

**Incremental delivery**: Add Phase 4 (US2) next to light up automatic metadata
extraction/persistence — the highest-value remaining capability. Finish with Phase 5
(US3) to harden and prove availability/privacy/observability, then Phase 6 to close out
documentation for the Constitution's Definition of Done (Principle XIV).
