# AWS Cloud-Native Insurance Document Upload Portal

A minimal, cloud-native MVP that lets an insurance customer upload a document through a
Flask web portal. The document is stored in a private S3 bucket; an S3 event
asynchronously triggers a Lambda function that extracts metadata and records it in a
private RDS PostgreSQL database. See `specs/001-insurance-document-upload-portal/` for
the full specification, plan, and task breakdown.

## Prerequisites

- An AWS account and credentials (`aws configure`) with permission to create VPC, EC2,
  ALB/ASG, S3, Lambda, RDS, and IAM resources.
- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.6.
- [AWS CLI](https://docs.aws.amazon.com/cli/) v2.
- `pip` (any Python 3.x) and `bash` available on the machine running `terraform apply` —
  used only to build the Lambda's `psycopg2-binary` layer (see Deployment Mechanics
  below); `pip` downloads a prebuilt Linux wheel and does not need to run on Linux
  itself. On Windows, Git Bash (installed with [Git for
  Windows](https://git-scm.com/downloads/win)) or WSL provides `bash` on `PATH`.
- `psql` (PostgreSQL client) if you want to query the metadata table directly during
  validation.

## Deployment

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set a real db_password and, optionally, region/AZs/project_name.
terraform init
terraform apply
```

Terraform provisions: a 2-AZ VPC (2 public / 2 private-app / 2 private-db subnets), an S3
Gateway VPC Endpoint, four security groups (ALB/EC2/Lambda/RDS), an ALB + Auto Scaling
Group running the Flask app, a private S3 bucket, a Lambda function wired to S3
ObjectCreated events, and a private RDS PostgreSQL instance with the `documents` table
bootstrapped automatically.

### Deployment Mechanics (how app/Lambda code actually reach AWS)

- **Lambda dependency layer**: `infra/lambda_layer.tf` runs `pip install ... --platform
  manylinux2014_x86_64 --python-version 3.11 --only-binary=:all:` as a Terraform
  `local-exec` provisioner (explicitly run via `bash -c`, so it behaves identically on
  Windows/macOS/Linux rather than falling back to `cmd.exe` on Windows), downloading a
  prebuilt `psycopg2-binary` wheel into `infra/build/layer/`, zips it, and publishes it
  as a Lambda Layer attached to the function (runtime `python3.11`). This re-runs
  automatically whenever `lambda/requirements.txt` changes — no manual step needed. The
  `infra/build/layer/python/` directory is tracked (via a `.gitkeep`) so `terraform
  plan` succeeds on a clean checkout, before the provisioner has populated it.
- **EC2 application code**: `infra/app_deploy.tf` zips `app/` (code, templates, static
  files, `requirements.txt`) via Terraform's `archive_file` and uploads it to
  `s3://<bucket>/app-artifacts/app_package.zip`. Every ASG instance's launch-template
  user-data (`infra/asg.tf`) downloads and unpacks that artifact and installs its
  dependencies on every boot — before starting the `flask-app` systemd service — so a
  freshly launched or replaced instance always runs the current code without needing
  CodeDeploy or any extra deployment service. To roll out an app code change, just
  `terraform apply` again (updates the S3 object) and cycle the ASG instances (e.g.,
  `aws autoscaling start-instance-refresh`).

Note the `alb_dns_name`, `s3_bucket_name`, `rds_endpoint`, and `lambda_function_name`
values from `terraform output` — they're used in Validation below.

## Validation

```bash
# 1. Health check
curl -i http://<alb_dns_name>/health
# Expect: 200 OK

# 2. Upload a test file via the browser at http://<alb_dns_name>/, or via curl:
curl -F "file=@/path/to/test.pdf" http://<alb_dns_name>/upload
# Expect: a success response

# 3. Confirm the object landed in S3
aws s3 ls s3://<s3_bucket_name>/uploads/

# 4. Confirm metadata was processed (allow up to 60s)
psql "host=<rds_endpoint_host> dbname=insurance_documents user=portal_admin" \
  -c "SELECT object_key, file_name, content_type, upload_timestamp FROM documents ORDER BY updated_at DESC LIMIT 5;"

# 5. Confirm Lambda logged the attempt
aws logs tail /aws/lambda/<lambda_function_name> --since 5m

# 6. Confirm the document store and metadata store are private
aws s3api get-object --bucket <s3_bucket_name> --key uploads/does-not-matter /dev/null --no-sign-request
# Expect: AccessDenied

aws rds describe-db-instances --db-instance-identifier <db_instance_id> \
  --query 'DBInstances[0].PubliclyAccessible'
# Expect: false
```

See `specs/001-insurance-document-upload-portal/quickstart.md` for the full 8-step
walkthrough, including how to exercise ALB health-check replacement.

## Demonstration

1. Open `http://<alb_dns_name>/` in a browser.
2. Select any file and click upload — a success message appears within seconds.
3. In another terminal, confirm the object is in S3 (`aws s3 ls`) and, within ~60
   seconds, that a matching row exists in the `documents` table (see step 4 above).
4. Tail the Lambda's CloudWatch logs (step 5 above) to see the processing outcome logged.
5. Confirm both RDS and S3 remain unreachable directly from the public internet (step 6
   above) throughout.

## Useful CloudWatch Metrics & Logs

| Component | Metrics to watch | Logs |
|---|---|---|
| ALB | `HealthyHostCount`, `UnHealthyHostCount`, `HTTPCode_Target_5XX_Count` | ALB access logs (optional, not enabled by default in this MVP) |
| EC2 / ASG | `CPUUtilization`, `GroupInServiceInstances`, `GroupDesiredCapacity` | `/insurance-doc-portal/app` CloudWatch log group (Flask stdout/stderr via CloudWatch agent) |
| Lambda | `Errors`, `Duration`, `Invocations`, `Throttles` | `/aws/lambda/<lambda_function_name>` |
| RDS | `DatabaseConnections`, `FreeStorageSpace`, `CPUUtilization` | RDS does not stream application logs for this MVP; connectivity is exercised only by Lambda |
| S3 | Request metrics (optional, not enabled by default) | S3 access logs not enabled by default in this MVP |

## Assumptions & Limitations

- No customer authentication — uploads are anonymous self-service, per spec.
- No file-size or file-type validation is enforced in the MVP; any file the customer
  selects is accepted and stored as-is (a deliberate, documented scope cut — see
  Production Enhancements below).
- The 50-concurrent-upload baseline (NFR-002) is a documented sizing assumption for this
  demo, not independently load-tested as part of this deliverable.
- Metadata upserts are keyed by S3 object key: a redelivered/duplicate S3 event updates
  the existing row rather than creating a duplicate.

## Production Enhancements (explicitly out of MVP scope)

These are intentionally deferred, not oversights — cost and scope discipline for this
MVP (Constitution Principles XI/XIII):

- **NAT Gateway**: not deployed; private application/database subnets have no outbound
  internet route. Add a NAT Gateway (or NAT instance) per AZ if outbound internet access
  (e.g., OS package updates) becomes necessary.
- **Multi-AZ RDS**: a single RDS instance is used; enable Multi-AZ for production
  failover.
- **File validation**: add a maximum upload size and a content-type allow-list, plus
  virus/content scanning, before accepting customer uploads in production.
- **Customer authentication**: tie uploads to an authenticated customer identity.
- **CloudWatch dashboards and alarms**: not created for the MVP; add alarms on ALB 5XX
  rate, Lambda `Errors`, and RDS `FreeStorageSpace` for production operations.
- **TLS/HTTPS**: the ALB listens on HTTP only for this MVP; add an ACM certificate and an
  HTTPS listener (plus HTTP→HTTPS redirect) for production.

## Cleanup

```bash
cd infra
terraform destroy
```

Confirm teardown completed:

```bash
aws s3 ls | grep <project_name>          # should return nothing for this project's bucket
aws rds describe-db-instances --query "DBInstances[?contains(DBInstanceIdentifier, '<project_name>')]"
# should return an empty list
```
