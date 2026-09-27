# Quickstart: Validate the AWS Cloud-Native Insurance Document Upload Portal

This guide proves the end-to-end flow described in spec.md's Demonstration section works,
once the feature is implemented and deployed. It does not contain implementation code —
see `tasks.md` for build steps.

## Prerequisites

- AWS account/credentials with permission to create VPC, EC2, ALB/ASG, S3, Lambda, RDS,
  and IAM resources.
- Terraform installed locally (version pinned in `infra/`).
- AWS CLI configured (`aws configure`) for the target account/region.

## 1. Deploy infrastructure

```bash
cd infra
terraform init
terraform apply
```

Expected outcome: Terraform completes with no errors and outputs the ALB DNS name.

## 2. Validate the portal is reachable (User Story 1 / SC-001, SC-002)

```bash
curl -i http://<ALB_DNS_NAME>/health
# Expect: 200 OK
```

Open `http://<ALB_DNS_NAME>/` in a browser, select a small test file (e.g., a PDF or
image under 5MB), and click upload.

Expected outcome: a success message appears in the browser within ~30 seconds.

## 3. Confirm the document landed in S3 (contracts/flask-http-api.md)

```bash
aws s3 ls s3://<document_bucket_name>/
```

Expected outcome: the uploaded object appears with a key matching what the UI reported.

## 4. Confirm metadata was processed (User Story 2 / SC-003, data-model.md)

```bash
psql "host=<rds_endpoint> dbname=<db_name> user=<db_user>" \
  -c "SELECT object_key, file_name, content_type, upload_timestamp FROM documents ORDER BY updated_at DESC LIMIT 5;"
```

Expected outcome: within 60 seconds of the upload, a row exists whose `object_key`
matches the S3 object from step 3, with correct `content_type` and a recent
`upload_timestamp`.

## 5. Confirm Lambda logging (SC-006)

```bash
aws logs tail /aws/lambda/<lambda_function_name> --since 5m
```

Expected outcome: a log line for the just-processed object showing a success outcome.

## 6. Confirm private-network isolation (User Story 3 / SC-004)

```bash
# From outside the VPC, direct access attempts must fail/time out:
aws s3api get-object --bucket <document_bucket_name> --key <some_key> /dev/null --no-sign-request
# Expect: AccessDenied (bucket is private, not anonymously readable)

# RDS should have no public endpoint reachable — confirm via:
aws rds describe-db-instances --db-instance-identifier <db_instance_id> \
  --query 'DBInstances[0].PubliclyAccessible'
# Expect: false
```

## 7. Confirm auto-scaling / health replacement (User Story 3 / SC-005)

Manually stop the application process on one EC2 instance (e.g., via SSM `sudo systemctl
stop <flask-service>`), then:

```bash
aws elbv2 describe-target-health --target-group-arn <target_group_arn>
```

Expected outcome: the stopped instance is reported unhealthy and is terminated/replaced
by the Auto Scaling Group without the portal becoming unreachable (test by repeating step
2 during this window).

## 8. Tear down

```bash
cd infra
terraform destroy
```

Expected outcome: all resources are removed; a subsequent `aws s3 ls` / `aws rds
describe-db-instances` for this feature's resources returns nothing.
