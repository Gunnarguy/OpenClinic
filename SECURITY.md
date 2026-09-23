# Security Policy: OpenClinic

OpenClinic is a local-first, native clinical workspace designed to handle patient clinical records on-device. This document outlines the security boundaries, storage models, data isolation principles, and processes for reporting security vulnerabilities.

---

## 1. Prototype Status & Safety Boundary

> [!WARNING]
> OpenClinic is currently a prototype. It is not approved for production clinical use, nor is it certified to handle real Protected Health Information (PHI) under HIPAA, GDPR, or other regional healthcare compliance standards. Do not deploy this application in a live medical environment or input real patient credentials.

---

## 2. Supported Versions

Only the latest release version on the `main` branch is actively supported and monitored for security issues:

| Version | Supported |
|---|---|
| `main` | :white_check_mark: Yes |
| All prior tags/branches | :x: No |

---

## 3. Secret Storage & API Credentials Model

OpenClinic requires connection tokens and endpoints to communicate with external SMART on FHIR servers. These parameters are stored using these guidelines:

* **OAuth Access & Refresh Tokens:** Stored securely in the iOS/macOS System Keychain. They are bound to the app's bundle identifier and are unavailable to other applications on the device.
* **Server Endpoints & Preferences:** Non-sensitive configuration options (such as the default FHIR server base URL, client identifier, and the `didClearLegacyDataV1` flag) are stored in standard `UserDefaults`.
* **Private API Keys:** The app does not utilize or store private cloud API keys (e.g. OpenAI or Anthropic keys) since all embeddings, tokenization, search indexing, and note generation run locally on-device.

---

## 4. Local Storage Risks & Data Isolation

All patient records are kept strictly in the local application sandbox:

* **SwiftData SQL Store:** Patient records are written to a SQLite file in the application's private container (`Library/Application Support/`), with no explicit file-protection class.
* **Vector Store Persistence:** Core ML embeddings generated for patient records are serialized directly to a flat binary file in the app sandbox.
* **Clinical Photos:** Patient photos imported or captured via camera are stored in the sandbox's Documents directory, mapped to specific `ClinicalPhoto` SwiftData model relationships.
* **Data Leakage Safeguards:** Subsystems are isolated. Patient UUIDs and category tags are attached to every data chunk to prevent cross-patient data mixtures during RAG retrievals (enforced by the `patientScope` filter for patient-scoped queries; `gatePatientIsolation` reports any mixture).

---

## 5. Network Boundary & Transmission Security

* **HTTPS Enforcement:** The network client (`FHIRClient`) enforces App Transport Security (ATS) rules. All connections to FHIR server endpoints must utilize HTTPS under default App Transport Security.
* **Authentication Sessions:** Interactive OAuth login uses `ASWebAuthenticationSession`. This presents the sign-in prompt within a system-controlled sandboxed web view, isolating credentials from the main application thread.
* **Callback Protection:** The app callback scheme (`medmod://smart-callback`) is registered in Info.plist to prevent hijack attacks by other local apps.

---

## 6. Observability & Logging Policy

System logs are captured using Apple's unified logging system via `os.Logger`. To prevent accidental data leaks in device logs (accessible via Xcode Console or Console.app):
* Interpolated values such as patient names are not marked public, so the system redacts them by default.
* Subsystem categories (such as `AI`, `Data`, `SMART`) are separated to allow granular filtering without exposing PHI.

---

## 7. Release-Build Safeguards

* **Mock Data Seeding:** Mock data is seeded whenever the patient database is empty, in every build configuration.
* **Compiler Settings:** The project builds in the Swift 5 language mode with approachable concurrency.

---

## 8. Reporting a Vulnerability

If you discover a security vulnerability or credential handling issue, **do not open a public GitHub issue.** Instead, please report it privately:

1. Contact the repository owner directly through the contact details listed on their GitHub profile page, or use GitHub's private vulnerability reporting feature if enabled.
2. Include a detailed description of the vulnerability, reproduction steps, and potential impacts.
3. **Important:** Redact all server names, credentials, token outputs, and patient identifiers from your report. Use synthetic mock data only.

---

## 9. Security Checklist for Future Changes

Developers submitting pull requests must verify their changes against this checklist:

* [ ] No hardcoded passwords, client secrets, or patient identifiers are checked into source code.
* [ ] All new network queries are wrapped in TLS/HTTPS.
* [ ] Any new patient-identifiable data fields are excluded from print statements or public logging.
* [ ] New database schemas define appropriate cascade deletions to prevent orphaned records.
* [ ] No new third-party Swift package manager dependencies are added without explicit audit approval.
