<!--
Sync Impact Report
Version change: N/A (template) → 1.0.0
Modified principles: N/A (initial ratification)
Added sections:
  - Core Principles I–XIV (Cloud-Native AWS Architecture, Infrastructure as Code,
    Security by Default, Least-Privilege Access, Network Isolation,
    High Availability and Scalability, Asynchronous Document Processing,
    Application Simplicity, Lambda Simplicity, Observability, Cost Awareness,
    Reproducibility and Documentation, Scope Discipline, Definition of Done)
  - Governance
Removed sections: Generic [SECTION_2_NAME]/[SECTION_3_NAME] placeholders (superseded by
  Principles VII–XIV which cover MVP scope, application, Lambda, observability, cost,
  documentation, and Definition of Done)
Templates requiring follow-up: none — this is the initial ratification, no dependent
  templates reference prior principle text.
Deferred items: none
-->

# AWS Cloud-Native Insurance Document Upload Portal Constitution

## Core Principles

### I. Cloud-Native AWS Architecture
The solution MUST use AWS managed services appropriately rather than self-managed
infrastructure where a managed equivalent exists. The architecture MUST prioritize
scalability, availability, security, and operational simplicity, in that order of
emphasis when trade-offs arise. The MVP MUST be deployable within a single AWS VPC
spanning exactly two Availability Zones.
**Rationale**: Managed services reduce operational burden and are consistent with an
assignment scope where engineering time is best spent on correctness, not undifferentiated
infrastructure maintenance.

### II. Infrastructure as Code
All AWS infrastructure MUST be defined using Terraform. Infrastructure MUST be
reproducible and MUST support both full deployment and complete teardown via Terraform
commands alone. Manual AWS console configuration MUST be avoided wherever Terraform is
capable of managing the resource.
**Rationale**: Reproducibility and clean teardown are required to avoid orphaned billable
resources and to let any engineer recreate the environment identically.

### III. Security by Default
No public access to S3 objects or RDS is permitted. S3 Block Public Access and
encryption MUST be enabled on all buckets. RDS instances MUST have public accessibility
disabled. Credentials and secrets MUST NOT be hard-coded in source, configuration, or
Terraform state committed to the repository. IAM roles and least-privilege permissions
MUST be used in place of static credentials wherever AWS supports it.
**Rationale**: Insurance documents are sensitive; default-secure infrastructure prevents
accidental data exposure regardless of downstream application bugs.

### IV. Least-Privilege Access
EC2 instances MUST use an IAM instance role rather than static AWS credentials. Lambda
MUST use a dedicated execution role scoped to its own function. Every IAM policy MUST
grant only the permissions required by the specific component it is attached to — broad
or wildcard permissions MUST be justified explicitly if used. Network access MUST be
restricted using security groups and subnet routing appropriate to each tier.
**Rationale**: Scoping permissions per component limits blast radius if any single
credential or role is compromised.

### V. Network Isolation
The architecture MUST use one VPC spanning two Availability Zones, with: two public
subnets for the internet-facing ALB; two private application subnets for EC2 instances;
and two private database subnets for RDS. RDS MUST NOT be reachable from the internet.
EC2 MUST NOT have direct database access. Only Lambda is permitted to connect to
PostgreSQL. An S3 Gateway VPC Endpoint MUST be used for private EC2-to-S3 access. A NAT
Gateway MUST NOT be deployed in the MVP due to cost constraints; NAT Gateway MUST be
documented as a production enhancement rather than silently added.
**Rationale**: Tiered subnet isolation with a documented, deliberate absence of NAT
Gateway enforces least-privilege network paths while keeping MVP cost low.

### VI. High Availability and Scalability
The web application MUST use an Application Load Balancer in front of an EC2 Auto
Scaling Group. Application capacity MUST span two Availability Zones. Health checks
MUST be configured so unhealthy instances are detected and automatically replaced. The
architecture MUST support scaling to handle peak traffic without manual intervention.
**Rationale**: ALB + ASG across two AZs is the minimum viable pattern for availability
and elasticity without introducing unnecessary orchestration complexity.

### VII. Asynchronous Document Processing
Uploaded documents MUST be stored in S3. S3 ObjectCreated events MUST trigger Lambda.
Lambda MUST process document metadata asynchronously, extracting file name, content
type, and upload timestamp, and MUST persist that metadata to RDS PostgreSQL. Failures
in this pipeline MUST be logged and MUST NOT silently discard processing information.
**Rationale**: Decoupling upload from metadata persistence via S3 events keeps the web
tier simple and makes failures observable rather than swallowed.

### VIII. Application Simplicity
The customer-facing application MUST be implemented in Python Flask. The UI MUST remain
intentionally simple, supporting only file selection, upload, and basic success/error
feedback. The application MUST expose exactly the endpoints `/`, `/health`, and
`/upload`. Unnecessary frameworks, microservices, or architectural complexity MUST be
avoided.
**Rationale**: The assignment's value is in correct cloud architecture, not UI or
framework sophistication; a minimal Flask app keeps the surface area reviewable.

### IX. Lambda Simplicity
The Lambda function MUST be implemented in Python and MUST perform only the required S3
metadata extraction and PostgreSQL persistence — no additional responsibilities. Lambda
MUST log meaningful success and failure information to CloudWatch for every invocation.
**Rationale**: A single-purpose Lambda is easier to reason about, test, and debug than
one that accumulates unrelated responsibilities over time.

### X. Observability
Application and Lambda activity MUST be observable through CloudWatch. Logs MUST
contain enough information to troubleshoot upload and processing failures, including
identifying context (e.g., object key, error detail) rather than generic messages.
Important AWS service metrics SHOULD be documented for reference. Dashboards and alarms
are optional MVP enhancements and are not required unless the implementation specifically
depends on them.
**Rationale**: Logs are the primary debugging tool for this MVP; dashboards/alarms are
valuable but not required to meet the Definition of Done.

### XI. Cost Awareness
The MVP MUST minimize unnecessary AWS costs. NAT Gateway and other expensive services
MUST be avoided where not strictly required. Multi-AZ RDS deployment MUST be avoided for
the MVP unless explicitly required. Any production improvement that increases cost MUST
be documented separately as a future enhancement rather than added silently to the MVP.
**Rationale**: This is a learning/assignment MVP, not a production system; cost
discipline keeps the exercise focused and avoids unbudgeted spend.

### XII. Reproducibility and Documentation
The repository MUST contain application code, Lambda code, Terraform infrastructure,
dependency manifests, and documentation. The README MUST explain prerequisites,
deployment steps, validation steps, a demonstration walkthrough, and cleanup steps.
Another engineer MUST be able to understand and reproduce the environment using only the
repository contents.
**Rationale**: An assignment deliverable is only as good as another engineer's ability to
independently stand it up, verify it, and tear it down.

### XIII. Scope Discipline
Implementation MUST cover only what is required for the assignment MVP. Simple,
maintainable solutions MUST be preferred over unnecessary enterprise complexity.
Terraform implementation details MUST NOT unnecessarily constrain functional
requirements. Production enhancements MUST be clearly separated from MVP requirements
(e.g., in a dedicated "Future Enhancements" section) rather than blended into MVP scope.
**Rationale**: Scope creep, whether from over-engineered infrastructure or from blending
"nice to have" production concerns into the MVP, obscures whether the core requirements
were actually met.

### XIV. Definition of Done
The project is complete only when all of the following hold:
- The Flask application is accessible through the ALB.
- A customer can upload a document, which is stored in S3.
- S3 triggers Lambda; Lambda extracts the required metadata and inserts it into private
  RDS PostgreSQL.
- Lambda logs execution information (success and failure) to CloudWatch.
- RDS is private and accessible only from Lambda.
- EC2 instances run in private application subnets, managed by an Auto Scaling Group
  behind an ALB, spanning two Availability Zones.
- IAM follows least privilege and security groups enforce the intended traffic flow.
- Terraform can both create and destroy the full infrastructure.
- Both application and Lambda source code are included in the final deliverable.
- Deployment, validation, demonstration, assumptions, limitations, and cleanup are
  documented in the repository.
**Rationale**: A single, checkable list prevents partial or ambiguous completion claims
and gives reviewers (and the implementer) an unambiguous acceptance bar.

## Governance

This constitution supersedes ad hoc practice for this project. Any conflict between this
document and other guidance (README, code comments, prior habit) is resolved in favor of
this constitution unless the constitution itself is amended.

**Amendment procedure**: Amendments are made by editing this file directly. Each
amendment MUST update the Sync Impact Report comment at the top of the file, bump the
version per the policy below, and update the Last Amended date.

**Versioning policy** (semantic versioning for governance):
- MAJOR: Backward-incompatible removal or redefinition of a principle.
- MINOR: A new principle or materially expanded guidance is added.
- PATCH: Wording clarifications, typo fixes, or non-semantic refinements.

**Compliance review**: Any plan, task breakdown, or implementation produced for this
project SHOULD be checked against these principles before being considered ready,
particularly Principles III–V (security/network isolation) and XIV (Definition of Done).
Deviations MUST be justified explicitly and, where they represent a deliberate MVP
trade-off (e.g., no NAT Gateway, single-AZ RDS), documented as such rather than treated
as oversights.

**Version**: 1.0.0 | **Ratified**: 2026-09-27 | **Last Amended**: 2026-09-27
