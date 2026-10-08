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
- [x] **9-Gate Safety Validator:** Evaluates retrieval confidence, contradictions, numeric grounding, and patient scope boundaries on the retrieved records before the model runs. The checks do not read or block generated text.
- [x] **Computed Panel Answers:** Set questions ("which patients ...") are parsed into structured queries and computed from chart facts by `CohortEngine`, with the source record behind every match and a hand-written evaluation set (`PanelQuestionEvalTests`).
- [x] **Fixture-Driven Demo Panel:** The synthetic panel lives in `DemoPanel.json` with coherence tests (ages against dates of birth, anatomical zones, ICD-10 format, same-day stability).
- [x] **SMART on FHIR Client:** ASWebAuthenticationSession integration with well-known configuration and CapabilityStatement discoveries, PKCE (S256), and refresh-token exchange.
- [x] **Full-Record FHIR R4 Import:** Ten resource types per patient with paging, retries, source-resource storage, and rows marked (not deleted) when the server stops returning them. Tested against responses captured from the SMART Health IT sandbox.
- [x] **Structured Chart:** Problems, allergies, vital signs, laboratory results, encounters, procedures, immunizations, reports, and documents as stored rows with provenance. The vitals flowsheet reads stored observations.
- [x] **Access Log:** Imports, source-resource views, and demo resets are recorded without clinical content.
- [x] **Dermatology Workflow:** Anatomical body region mapping, lesion visual timelines, and photo attachments.
- [x] **PDF Note Export:** Native generation of visit-note PDFs once documentation is signed.
- [x] **Token Budget Management:** Query-intent classification and batch recursive RAG synthesis to stay within 4096-token limits.
- [x] **XCTest Suite Integration:** Automated unit tests against synthetic inputs and responses captured from the SMART Health IT sandbox, run by `./Scripts/verify.sh` (191 tests on 2026-10-07). No test covers the 9 retrieval checks yet.
- [x] **iOS / iPadOS / macOS / visionOS Port:** Full multi-platform compatibility across iOS, iPadOS, macOS, and visionOS.

### Active Work
- [ ] **Verify Generated Answers:** Run the gates on the model's answer, not only on the retrieved context, and withhold or flag an answer that fails. Until then the app labels every model-written answer as unchecked.
- [ ] **Multi-Pass "Deep Think" Retrieval:** Optimizing query expansion heuristics to pull broader histories for complex panel questions.
- [ ] **Core ML Inference Performance:** Speeding up embedding generation times on standard Apple Silicon devices.
- [ ] **visionOS Spatial Enhancement:** Converting the 2D anatomical body maps into native RealityKit spatial models.

### Planned Improvements
- [ ] **Outbound FHIR Sync:** Adding writeback capability to upload signed visit notes as FHIR `DocumentReference` resources.
- [ ] **Biometric Access Gate:** Adding FaceID/TouchID checks before exposing local SwiftData databases.
- [ ] **HNSW Vector Indexing:** Upgrading the linear-scan vector store to a scalable graph index for panels exceeding 1,000 patient records.

---

## 3. Known Limitations & Technical Debt

* **Index Sync:** Launch embeds only the chart text that changed since the index was saved: 1.07 s for an unchanged 615-chunk index in the iOS 27.0 Simulator on 2026-10-07, against 118.7 s for the full rebuild it replaced. On an iPhone 16 Pro Max the first index of the demo panel (291 chunks) took 3.2 s and a later launch 0.3 s. An edit made in the app reaches the index at the next launch, record import or "Reindex"; nothing syncs after each edit yet. The demo panel's dates move with the calendar and sit in the indexed text, so the first launch of a day embeds most demo chunks again (261 of 291 in 4.9 s on a Mac on 2026-10-08). A patient whose embedding fails stops that launch's sync before the keyword-index repair.
* **No HealthKit:** The HealthKit entitlement and purpose strings were removed on 2026-10-07; no code used them. HealthKit is designed for personal device owners, whereas OpenClinic is a multi-patient practitioner workspace.
* **Import-Only Interoperability:** Synchronization is unidirectional (from FHIR server to local SwiftData). There is no outbound writeback path implemented.
* **Engine Lineage:** The retrieval stack is an adaptation of OpenIntelligence's, kept in this repository. Embedding the OpenIntelligence engine package itself is not done; it needs changes in that package first.
* **FHIR Read Layer, Open Points:** A date given only to the year or month keeps that precision for a problem's onset and abatement, a procedure's start, an immunization, and a patient's dates of birth and death; every other date is stored as the first day of the period and the import says so. Rows and source resources keep the spelling of the server address they were stored under; a later import finds them when the address differs only in letter case, a default port or a trailing slash, and nothing rewrites the stored ids. A year-only date of birth gives an age shown as "about". A government number shorter than four characters is left in a Patient resource's narrative text. A sign-in asks for `offline_access` only from a server that says it issues refresh tokens; a refresh token is held in memory, so a sign-in does not outlast the app's run. A resource server that refuses a request is covered only by stubbed tests: the SMART launcher answers a read that carries no token. A deceased patient is still counted by panel questions, at the age of death when the date of death is known. A year-only date of birth is treated as January 1 by age questions. A store that was set aside as unreadable and later put back by hand is not passed through the one-time repair of earlier imports.
* **macOS Sandbox:** The Mac target is sandboxed with one entitlement, outgoing network connections, added on 2026-10-08 so the Mac build can reach a FHIR server (checked by `./Scripts/verify.sh live`, which runs in that sandbox). Before that the host lookup was refused.
* **The On-Device Model Declines Some Requests:** Apple's on-device model refuses a request it classes as sensitive ("May contain sensitive content"). On 2026-10-07 it refused every patient question and every dictated note in the form the app then used; in the form the app uses now (a record and a question, or a dictation alone, with no clinical role-play) it answered every one in the same tests. When it declines, the app lists the patient's chart rows or sorts the dictation's own sentences into the note's sections, and labels the text as that. Which requests it declines can change with an operating system update, and only the device self-check (`./Scripts/verify.sh device`) shows it.
* **Decision Support Rules:** The alert rules on the chart summary are written inline in the view and have no tests.
* **No Vitals or Results Entry:** Vital signs and results are imported or seeded. There is no screen to enter them.
* **In-Memory Messages:** IntraMail messages are not persisted.
* **Swift 5 Language Mode:** The project compiles in Swift 5 mode with several `@unchecked Sendable` types. Swift 6 mode is not enabled.
* **No Multi-User Support:** The SwiftData database is configured for single-clinician execution in a local app sandbox. There is no multi-user sync or enterprise role-based access control (RBAC).

---

## 4. Release Readiness Checklist

This checklist tracks requirements needed before transitioning OpenClinic from a prototype to a production build:

- [ ] **Security Auditing:** Conduct an independent penetration test of ASWebAuthenticationSession and the Keychain storage layer.
- [ ] **Regulatory Compliance:** Establish full audit trails, automatic logouts, and encryption-at-rest profiles for HIPAA/GDPR validation.
- [ ] **Clinical Validation Suite:** Run systematic correctness audits on structured notes generated from diverse voice dictations.
- [ ] **Automated CI/CD:** Establish GitHub Actions to automate builds, code quality checks, and dependency validations.
- [ ] **Outbound FHIR Integration:** Implement and test FHIR resource writebacks with sandboxed Epic/Cerner systems.
