# Roadmap: OpenClinic

OpenClinic is a research prototype and system design evaluation workspace for native, on-device clinical workflows on Apple platforms. This document lists completed implementation milestones, active work items, known limitations, and development priorities.

---

## 1. Project Status

* **Current Maturity:** Functional Prototype / Development Build.
* **Target Audience:** Developers, system designers, and technical clinical coordinators.
* **Safety Disclaimer:** Not approved for clinical use or live deployment with patient data.

---

## 2. Milestones

### Completed
- [x] **SwiftData Schema:** Persistence structure mapping Patients, Clinical Records, Medications, Appointments, and Photos.
- [x] **Local RAG Indexer:** Segment clinical records, run local Core ML embeddings (`EmbeddingModel.mlpackage`), index keywords using SQLite FTS5, and serialize vector arrays to the local app sandbox.
- [x] **9-Gate Safety Validator:** Evaluates retrieval confidence, contradictions, numeric grounding, and patient scope boundaries before displaying LLM outputs.
- [x] **SMART on FHIR Client:** ASWebAuthenticationSession integration with well-known configuration and CapabilityStatement discoveries.
- [x] **Dermatology Workflow:** Anatomical body region mapping, lesion visual timelines, and photo attachments.
- [x] **PDF Note Export:** Native generation of visit-note PDFs once documentation is signed.
- [x] **Token Budget Management:** Query-intent classification and batch recursive RAG synthesis to stay within 4096-token limits.
- [x] **XCTest Suite Integration:** Automated unit tests to validate the 9 verification gates against synthetic inputs.
- [x] **macOS Catalyst Port:** Full multi-platform compatibility across iOS, iPadOS, and macOS.

### Active Work
- [ ] **Multi-Pass "Deep Think" Retrieval:** Optimizing query expansion heuristics to pull broader histories for complex panel questions.
- [ ] **Core ML Inference Performance:** Speeding up embedding generation times on standard Apple Silicon devices.
- [ ] **visionOS Spatial Enhancement:** Converting the 2D anatomical body maps into native RealityKit spatial models.

### Planned Improvements
- [ ] **Outbound FHIR Sync:** Adding writeback capability to upload signed visit notes as FHIR `DocumentReference` resources.
- [ ] **Biometric Access Gate:** Adding FaceID/TouchID checks before exposing local SwiftData databases.
- [ ] **HNSW Vector Indexing:** Upgrading the linear-scan vector store to a scalable graph index for panels exceeding 1,000 patient records.

---

## 3. Known Limitations & Technical Debt

* **Launch-time Index Rebuilds:** The app currently triggers a full reindex of all clinical records on every launch. This is suitable for small datasets but must be optimized to incremental updates for clinical production database sizes.
* **HealthKit Sync Code Deprecation:** The codebase retains the legacy HealthKit entitlement (`com.apple.developer.healthkit`), but HealthKit synchronization logic has been deprecated. HealthKit is designed for personal device owners, whereas OpenClinic is a multi-patient practitioner workspace.
* **Import-Only Interoperability:** Synchronization is unidirectional (from FHIR server to local SwiftData). There is no outbound writeback path implemented.
* **No Multi-User Support:** The SwiftData database is configured for single-clinician execution in a local app sandbox. There is no multi-user sync or enterprise role-based access control (RBAC).

---

## 4. Release Readiness Checklist

This checklist tracks requirements needed before transitioning OpenClinic from a prototype to a production build:

- [ ] **Security Auditing:** Conduct an independent penetration test of ASWebAuthenticationSession and the Keychain storage layer.
- [ ] **Regulatory Compliance:** Establish full audit trails, automatic logouts, and encryption-at-rest profiles for HIPAA/GDPR validation.
- [ ] **Clinical Validation Suite:** Run systematic correctness audits on structured notes generated from diverse voice dictations.
- [ ] **Automated CI/CD:** Establish GitHub Actions to automate builds, code quality checks, and dependency validations.
- [ ] **Outbound FHIR Integration:** Implement and test FHIR resource writebacks with sandboxed Epic/Cerner systems.
