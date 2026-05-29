# Privacy Policy: OpenClinic

**Last Updated: May 2026**

OpenClinic is a local-first clinical workspace for healthcare providers. We believe clinical tools should respect clinician privacy and patient confidentiality. This document outlines our data-handling practices in plain language.

---

## 1. Privacy-First Thesis

OpenClinic is designed so that **your clinical data stays on your device**. The application does not utilize a central database, does not sync data to private cloud storage, and does not sell or share patient records. All database processing, indexing, and generative model inference are conducted locally within the application's secure sandbox.

---

## 2. What Data Is Collected?

OpenClinic does not collect or track any patient data. 
* **User-Initiated Synced Data:** If you configure a live connection to a SMART on FHIR server, the app imports patient records, medications, appointments, and allergies directly to your local database context. This data is used solely to render the patient dashboard and intelligence interface.
* **Clinician Inputs:** Dictation voice recordings, transcribed text, typed notes, and camera-captured photos are processed and stored directly in your local iOS/macOS sandbox.

---

## 3. What Data Stays Local?

The following data types never leave your physical device:
* **Patient Profiles & Demographics:** Names, medical record numbers, dates of birth, and genders stored in SwiftData.
* **Clinical Records & HPI:** Encounter drafts, assessment summaries, signed notes, and follow-up plans.
* **Prescriptions & Meds:** Active medication records and refills.
* **Clinical Photo Library:** Images captured or imported for lesion tracking and dermatology body mapping.
* **Core ML Embeddings & Indexes:** Vector representations generated for search indexing, as well as SQLite FTS5 index files.
* **Model Inference Output:** Text summaries, structured note generations, and assistant answers compiled by on-device LLMs.

---

## 4. What Data Is Sent to External Services?

OpenClinic only initiates outbound network queries under the following circumstances:
1. **SMART Discovery & OAuth:** The app queries the FHIR base URL entered by the clinician (e.g. `https://launch.smarthealthit.org/...`) to fetch configuration statements. It opens ASWebAuthenticationSession to authenticate the clinician.
2. **EHR Data Sync:** When the clinician initiates an import, the app requests patient records from the selected FHIR server.

*No data is sent to OpenAI, Anthropic, or other third-party LLM cloud APIs. All intelligent generations utilize local, on-device Apple Foundation Models.*

---

## 5. How Credentials and Tokens Are Protected

* SMART on FHIR access tokens and authorization codes are saved in the device **Keychain** using hardware-accelerated encryption.
* Non-credential settings (such as preset selections and patient list filters) are kept in **UserDefaults**.

---

## 6. How Users Can Delete or Reset Data

OpenClinic provides a complete reset path:
1. **One-Time DB Reset:** If SwiftData migrations fail or legacy duplicates are detected, OpenClinic wipes the database files (`.sqlite`, `-wal`, `-shm`) on the next boot, recreating a fresh store.
2. **App Deletion:** Deleting the OpenClinic app from iOS or macOS automatically deletes all sandboxed files, database sqlite containers, Keychain tokens, and clinical photos permanently. No data is stored in iCloud backups if iCloud sync is disabled for the application.

---

## 7. Standard Privacy Profile

For deployment configurations, the privacy characteristics map as follows:

| Category | Status | Details |
|---|---|---|
| **Data Collection** | **No Data Collected** | The app does not transmit any user or patient identifiers to the developer or third-party tracking services. |
| **Data Linked to User** | **Not Linked** | Any imported FHIR resources or local notes are stored locally and are not linked to the clinician's Apple ID or device identity. |
| **Data Used for Tracking** | **No** | The app does not contain advertising SDKs, tracking libraries, or analytics scripts. |
| **Permissions Required** | **Camera, Microphone** | Requested only when the user initiates photo capture or dictation workflows. |
