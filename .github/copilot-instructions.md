# Copilot Instructions: OpenClinic

## 1. Project Identity

OpenClinic is a native Swift/iOS clinical workspace built with SwiftUI and SwiftData. It combines patient charting, encounter notes, dermatology-focused visual timelines, SMART on FHIR synchronizations, and an on-device local RAG (Retrieval-Augmented Generation) pipeline using Core ML embeddings and Apple's Foundation Models framework. The project is a prototype for evaluating native, on-device clinical software architectures on Apple platforms.

---

## 2. Prime Directives

* **Data Stays Local:** Maintain the local-first security boundary. Never write integrations that transmit patient records or clinician dictation to external cloud LLM APIs.
* **Clinical Correctness & Grounding:** When modifying prompts or generation routines, always enforce verification via the 9-gate evaluator ([VerificationGates.swift](OpenClinic/RAG/VerificationGates.swift)).
* **HIPAA/PHI Safety:** Do not log patient-identifiable data in plain text. Always mark names, MRNs, and chief complaints as `{private}` in OS Logger layouts.
* **No Speculation:** Describe, build, and document only what exists in the codebase. Do not invent remote servers, database entities, or features unless explicitly requested.

---

## 3. Architecture Rules

* **Concurrency Safety:** Enforce Swift 6 structured concurrency. Database indexing, Core ML generation, and vector store searches must run on background actors to avoid locking the SwiftUI main thread.
* **SwiftData Bindings:** Expose persistent properties via native SwiftData models and query them using SwiftUI `@Query` properties.
* **Decoupled Views:** Keep layouts modular. Avoid massive monolithic structures in view files; divide screens into reusable subviews and pass data through standard state variables.

---

## 4. Key Files by Concern

* **App Bootstrapping:** [OpenClinicApp.swift](OpenClinic/OpenClinicApp.swift)
* **Main UI Navigation:** [ContentView.swift](OpenClinic/ContentView.swift)
* **Encounter Editor:** [ClinicalExamView.swift](OpenClinic/Views/ClinicalExamView.swift)
* **RAG Orchestrator:** [ClinicalRAGService.swift](OpenClinic/RAG/ClinicalRAGService.swift)
* **On-Device LLM Handler:** [ClinicalIntelligenceService.swift](OpenClinic/AI/ClinicalIntelligenceService.swift)
* **Safety Evaluation:** [VerificationGates.swift](OpenClinic/RAG/VerificationGates.swift)
* **FHIR Ingestion:** [FHIRImportService.swift](OpenClinic/Interop/FHIR/FHIRImportService.swift)
* **OAuth Controller:** [SMARTConnectionController.swift](OpenClinic/Interop/SMART/SMARTConnectionController.swift)

---

## 5. Build and Validation Commands

To build the iOS target locally via command line:
```bash
xcodebuild -project OpenClinic.xcodeproj -scheme OpenClinic -sdk iphonesimulator build
```

*Note: The project does not currently contain automated unit test targets. All functional validations must be executed via manual simulator flows.*

---

## 6. Development Rules

* **Update Documentation:** If you modify database schemas (`Models/`), sync controllers (`Interop/`), or verification gates (`RAG/`), you must update `ARCHITECTURE.md` and `README.md` to keep documentation in sync.
* **Mask Secrets:** If coding templates contain credentials or token segments, automatically mask them in the source code using `[REDACTED_SECRET]` placeholders.
* **Preserve Documentation Integrity:** Do not overwrite or delete existing documentation files or comments unless explicitly requested.
