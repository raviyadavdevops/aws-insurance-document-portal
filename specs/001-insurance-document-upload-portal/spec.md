# Feature Specification: AWS Cloud-Native Insurance Document Upload Portal

**Feature Branch**: `001-insurance-document-upload-portal`

**Created**: 2026-09-27

**Status**: Draft

**Input**: User description: "Build an AWS Cloud-Native Insurance Document Upload Portal for an insurance company's customer self-service document submission workflow — customer uploads a document via a Flask web portal, the document is stored in S3, an S3 ObjectCreated event triggers a Lambda function that extracts metadata and persists it to a private RDS PostgreSQL database, all behind an ALB/ASG in a two-AZ VPC with private application and database subnets, least-privilege security, no NAT Gateway in the MVP, and full Terraform reproducibility."

## Clarifications

### Session 2026-09-27

- Q: Should the upload endpoint enforce the 25 MB file-size cap and the accepted file-type list (PDF/JPG/PNG) at the application layer, or should any file type/size be accepted for this MVP? → A: No enforced limits in MVP — accept any file/size, defer validation to production.
- Q: When a document metadata record already exists for the same object key (e.g., a Lambda retry redelivers the same S3 event), should the system update the existing record in place, or insert a new record every time? → A: Upsert — same object key overwrites/updates the existing metadata record.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Customer uploads an insurance document (Priority: P1)

An insurance customer visits the web portal, selects a document from their device (e.g.,
identity proof, claim form, or supporting evidence), and submits it. The customer sees a
clear success message once the upload completes, or a clear error message if it fails.

**Why this priority**: This is the entire purpose of the system — without a working upload
path, there is no product. All other capabilities (metadata processing, storage, observability)
exist to support this core interaction.

**Independent Test**: Can be fully tested by opening the portal through its public URL,
selecting a file, clicking upload, and confirming a success status is displayed and the file
is retrievable from storage. Delivers value on its own even before metadata processing is
verified.

**Acceptance Scenarios**:

1. **Given** the customer is on the upload page, **When** they select a valid document file and
   click upload, **Then** the system displays a success confirmation.
2. **Given** the customer is on the upload page, **When** they click upload without selecting a
   file, **Then** the system displays a clear error message and does not attempt an upload.
3. **Given** an upload is in progress, **When** the upload completes, **Then** the document is
   present in the document storage location under a unique, retrievable identifier.
4. **Given** the customer is on the upload page, **When** the underlying storage or network is
   unavailable, **Then** the system displays a clear, non-technical error message without
   exposing internal system details.

---

### User Story 2 - Document metadata is automatically extracted and recorded (Priority: P2)

After a document is stored, the system automatically extracts key metadata about the
document (file name, content type, upload timestamp) and records it in a durable,
queryable store, without requiring any additional customer action.

**Why this priority**: This enables the insurance company to track and later process
submitted documents. It is essential to the business workflow but happens after — and is
decoupled from — the customer-facing upload itself, so it is independently testable and
deployable once uploads work.

**Independent Test**: Can be fully tested by uploading a document (via User Story 1 or by
placing an object directly in storage) and then querying the metadata store to confirm a
corresponding record was created with the correct file name, content type, and timestamp.

**Acceptance Scenarios**:

1. **Given** a document has been successfully stored, **When** the storage event fires,
   **Then** a metadata record is created containing the file name, content type, and upload
   timestamp within a short, bounded delay.
2. **Given** metadata processing fails for a given document (e.g., malformed object,
   transient downstream failure), **When** the failure occurs, **Then** the failure is
   logged with enough detail to diagnose it, and no partial or corrupted metadata record is
   left behind.
3. **Given** the metadata store already contains a record for a given document, **When** a
   duplicate processing event occurs for the same object, **Then** the system updates the
   existing record for that object key in place rather than creating a second, conflicting
   record.

---

### User Story 3 - System remains available and private under normal operation (Priority: P3)

The insurance company's operations stakeholders need confidence that the portal stays
reachable during traffic fluctuations, that customer documents and metadata are never
exposed publicly, and that troubleshooting information is available when something goes
wrong.

**Why this priority**: Availability, privacy, and observability are cross-cutting
qualities rather than a standalone user-facing feature — they matter once the core flow
(Stories 1–2) exists, and are what make the system trustworthy enough to operate.

**Independent Test**: Can be tested independently by (a) verifying the document store and
metadata store are unreachable from the public internet through direct access attempts,
(b) simulating an unhealthy application instance and confirming it is detected and
replaced without customer-visible downtime, and (c) confirming logs exist for both a
successful and a failed processing attempt.

**Acceptance Scenarios**:

1. **Given** the system is deployed, **When** an unauthenticated party attempts to access
   the document store or metadata store directly from the public internet, **Then** the
   attempt is refused.
2. **Given** the application is under increased load, **When** demand rises, **Then**
   additional application capacity becomes available without manual intervention and
   without customer-visible failure.
3. **Given** one application instance becomes unhealthy, **When** the health check fails
   repeatedly, **Then** that instance is removed from service and replaced automatically.
4. **Given** a document has been processed (successfully or not), **When** an operator
   inspects the system's logs, **Then** they can find enough detail to determine what
   happened to that specific document.

### Edge Cases

- What happens when a customer uploads a file with no content (0 bytes) or an empty file
  name? System MUST reject the upload with a clear error before it is treated as stored.
- What happens when a customer uploads an extremely large file or an unexpected file
  type? The MVP intentionally does not enforce a maximum size or a file-type allow-list
  (see Assumptions); such validation is deferred to a future production enhancement.
- What happens when two customers upload files with the identical file name at the same
  time? System MUST store both without one overwriting the other's metadata record.
- What happens when the metadata-processing step cannot reach the metadata store (e.g.,
  it is temporarily unavailable)? The failure MUST be logged with enough detail to
  identify the affected document, and MUST NOT be silently dropped.
- What happens when a customer refreshes or closes the browser mid-upload? The system
  MUST NOT leave the customer in an ambiguous state — a subsequent visit to the portal
  MUST show a normal upload page, not a stuck or corrupted view.
- What happens when an uploaded file's declared type doesn't match its actual content?
  The system records the declared content type as provided; deep content inspection is
  out of scope for the MVP (see Assumptions).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide a web page where a customer can select a single
  document file from their device.
- **FR-002**: The system MUST provide an upload action that transmits the selected file
  and stores it in a private document store.
- **FR-003**: The system MUST display a success indicator to the customer when an upload
  completes and the document is durably stored.
- **FR-004**: The system MUST display a clear, non-technical error indicator to the
  customer when an upload fails for any reason (no file selected, file rejected, storage
  unavailable, etc.).
- **FR-005**: The system MUST expose a health-check capability that reports whether the
  customer-facing application is able to serve traffic.
- **FR-006**: The system MUST NOT require the customer to authenticate or create an
  account to submit a document in the MVP (self-service, low-friction submission).
- **FR-007**: The system MUST automatically detect when a new document has been stored,
  without requiring any manual trigger.
- **FR-008**: Upon detecting a newly stored document, the system MUST extract and persist
  at minimum: the file name (or object identifier), the content type, and the upload
  timestamp.
- **FR-009**: The system MUST persist extracted metadata to a durable, structured,
  queryable store separate from the document store itself, upserting on the document's
  object key so a redelivered or duplicate processing event updates the existing record
  rather than creating a second, conflicting one.
- **FR-010**: The system MUST process each newly stored document's metadata
  asynchronously — the customer-facing upload MUST NOT block or wait on metadata
  processing to complete.
- **FR-011**: The system MUST log a record of every metadata-processing attempt,
  including enough detail to identify the affected document, whether processing
  succeeded or failed, and — on failure — the reason.
- **FR-012**: The system MUST NOT silently discard a metadata-processing failure; every
  failure MUST be observable after the fact via logs.
- **FR-013**: The document store MUST NOT be reachable or readable by unauthenticated
  parties over the public internet.
- **FR-014**: The metadata store MUST NOT be reachable from the public internet under any
  circumstance.
- **FR-015**: The metadata store MUST only be reachable by the metadata-processing
  component; the customer-facing application MUST NOT have direct connectivity to it.
- **FR-016**: The system does NOT enforce a maximum file size or a file-type allow-list
  in the MVP; any file size or declared content type submitted by the customer is
  accepted (see Assumptions — deferred to a future production enhancement).
- **FR-017**: The system MUST reject uploads with no selected file or an empty payload
  with a clear customer-facing error, without creating a document-store entry.
- **FR-018**: The customer-facing application MUST run with multiple concurrent
  instances distributed across at least two independent physical locations (Availability
  Zones), so the loss of one location does not take the portal offline.
- **FR-019**: The system MUST automatically detect an unhealthy application instance and
  remove/replace it without requiring manual operator action.
- **FR-020**: The system MUST be able to increase the number of running application
  instances automatically as customer demand increases, and decrease it as demand falls.
- **FR-021**: The system MUST NOT require or store long-lived static credentials in
  application or processing code to access the document store or metadata store; access
  MUST be obtained through short-lived, component-scoped identity mechanisms.
- **FR-022**: Every infrastructure component MUST be provisionable and fully removable
  through a repeatable, automated process (no manual, undocumented setup steps).
- **FR-023**: The repository deliverable MUST include the customer-facing application
  source, the metadata-processing component source, the infrastructure definitions, all
  dependency manifests, and documentation covering setup, validation, demonstration, and
  teardown.

### Non-Functional Requirements

- **NFR-001 (Availability)**: The customer-facing portal MUST remain reachable if any
  single application instance or any single Availability Zone's application capacity is
  lost.
- **NFR-002 (Scalability)**: The system MUST support a documented target of at least 50
  concurrent document uploads without customer-visible failure (see Assumptions for
  baseline sizing; exact peak numbers are a tuning decision, not a scope-defining one).
- **NFR-003 (Processing Latency)**: Under normal operation, metadata extraction and
  persistence for a newly stored document MUST complete within 60 seconds of the document
  being stored, for at least 99% of uploads.
- **NFR-004 (Durability)**: A document that is confirmed to the customer as "uploaded"
  MUST NOT be lost due to a transient failure elsewhere in the system (e.g., a metadata
  processing outage must not cause the underlying document to disappear).
- **NFR-005 (Observability)**: Every successful and failed metadata-processing attempt,
  and every application-level error surfaced to a customer, MUST be captured in logs
  retrievable by an operator without direct access to running infrastructure.
- **NFR-006 (Cost Discipline)**: The MVP deployment MUST avoid infrastructure components
  whose primary purpose is redundancy/throughput beyond what the demonstration requires
  (e.g., no outbound internet gateway for private compute, no multi-region replication, no
  standby database replica) — see Constraints.
- **NFR-007 (Simplicity)**: The customer-facing UI MUST require no more than two
  customer actions (select file, click upload) to complete a submission.

### Security Requirements

- **SEC-001**: The document store MUST have public access blocked at the storage-service
  level (not merely at the application level).
- **SEC-002**: Documents MUST be encrypted at rest in the document store.
- **SEC-003**: The metadata store MUST be configured so it has no public network
  accessibility.
- **SEC-004**: Network traffic MUST be segmented such that: public traffic can only reach
  the load-balancing tier; the load-balancing tier is the only source permitted to reach
  the application tier; and the metadata-processing component is the only source
  permitted to reach the metadata store.
- **SEC-005**: The application tier MUST NOT have any network path to the metadata store.
- **SEC-006**: Each system component (application tier, metadata-processing component)
  MUST operate under its own distinct, least-privilege identity — no component may hold
  permissions it does not need for its specific function.
- **SEC-007**: No credentials, connection secrets, or access keys MUST appear in source
  code, configuration files, or version control history.
- **SEC-008**: Customer-uploaded content MUST NOT be servable back to the public internet
  directly from the document store.

### Error-Handling Expectations

- **ERR-001**: All customer-facing errors MUST use plain, non-technical language and MUST
  NOT expose internal identifiers, stack traces, or infrastructure details.
- **ERR-002**: A failure in metadata processing MUST NOT surface as a customer-visible
  upload failure — the customer's upload has already succeeded once the document is
  stored; processing failures are an operational concern, not a customer-facing one.
- **ERR-003**: Every processing failure MUST include, at minimum, enough context (which
  document, when, what failed) for an operator to locate and resolve the root cause
  without needing to reproduce the failure first.
- **ERR-004**: Transient failures in metadata processing SHOULD be distinguishable in
  logs from permanent/data-related failures, so operators can tell "retry may help" apart
  from "this document needs manual attention."

## Assumptions

- **Customer identity**: Customers are not required to log in for the MVP; the workflow
  is anonymous self-service submission. Tying uploads to a known customer identity is a
  plausible production enhancement, not an MVP requirement.
- **File size and type validation**: The MVP intentionally does not enforce a maximum
  upload size or restrict accepted file types — any file the customer selects is
  accepted and stored as-is. Size limits, file-type allow-lists, and deep content/virus
  inspection are explicitly deferred to a future production enhancement, not required to
  demonstrate the MVP workflow.
- **Scale baseline**: "Peak traffic" for this MVP is interpreted as a modest demonstration
  load (tens of concurrent users), not an enterprise-scale production load. NFR-002's
  concrete number is a documented assumption to make the requirement testable, not a
  contractual SLA.
- **Retention**: Documents and metadata records persist indefinitely for the MVP; a
  retention/deletion policy is a production concern, not required to demonstrate the
  workflow.
- **Duplicate submissions**: A customer may resubmit the same logical document more than
  once; the MVP treats each submission as a new, independent record rather than
  deduplicating across submissions.
- **Cost-driven omission**: Outbound internet access for the private application tier
  (e.g., for OS/package updates from the public internet) is intentionally not provided
  in the MVP due to cost constraints; this is a documented, deliberate trade-off rather
  than an oversight.

## Constraints

- The MVP MUST NOT rely on a component whose sole purpose is providing outbound internet
  access for private compute (cost constraint); any such capability is documented as a
  future production enhancement rather than added to the MVP.
- The MVP MUST NOT rely on standby/multi-instance redundancy for the metadata store
  beyond a single active instance (cost constraint); documented as a future production
  enhancement.
- The MVP MUST be demonstrable end-to-end (customer upload through metadata persistence
  and log visibility) using only automated, repeatable provisioning — no manual
  configuration steps that aren't captured in the reproducible setup process.
- The solution MUST avoid introducing additional user-facing services, workflows, or
  approval steps beyond select-file → upload → confirmation.

## Key Entities

- **Document**: A customer-submitted file (identity proof, claim form, or supporting
  evidence). Key attributes: unique storage identifier/object key, content type, size,
  upload timestamp. Stored in the document store; not directly queryable by structured
  fields.
- **Document Metadata Record**: A structured record describing a stored Document. Key
  attributes: unique record identifier, file name/object key (unique — the upsert key),
  content type, upload timestamp. Stored in the metadata store; one record MUST
  correspond to one stored Document's object key, with reprocessing of the same key
  updating that record rather than creating a duplicate.
- **Processing Log Entry**: An observability record describing one metadata-processing
  attempt for a Document. Key attributes: which document it concerns, outcome
  (success/failure), timestamp, failure reason (if applicable).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A customer can go from opening the portal to seeing an upload success
  confirmation in under 30 seconds for a typical document (under 5 MB) on a standard
  broadband connection.
- **SC-002**: 100% of documents that receive a customer-visible success confirmation are
  verifiably present in the document store afterward.
- **SC-003**: At least 99% of successfully stored documents have a corresponding,
  accurate metadata record created within 60 seconds, measured over a demonstration run
  of at least 20 uploads.
- **SC-004**: 0% of attempts to access the document store or metadata store directly from
  the public internet (bypassing the application) succeed.
- **SC-005**: When one application instance is intentionally made unhealthy, customer
  traffic experiences no failed requests, and the unhealthy instance is replaced without
  manual intervention within a documented, bounded time window.
- **SC-006**: 100% of metadata-processing failures during a demonstration run are
  discoverable in logs, each with enough detail to identify the specific affected
  document, without needing to inspect running infrastructure directly.
- **SC-007**: An engineer unfamiliar with the deployment can follow the repository's
  documentation to provision the full environment, complete one end-to-end demonstration
  upload, and fully tear down the environment, using only the documented steps.
