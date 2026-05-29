# App Store Reviewer Guide: OpenClinic

OpenClinic is a provider-facing, local-first clinical workspace. Since the application handles patient context synchronization and local AI processing, this guide provides the necessary credentials, sandbox configurations, and permissions notes for App Store review compliance.

---

## 1. Quick Testing Summary

To evaluate all features of the application (including local RAG generation and external sync) without a local hospital network connection:
1. Open the application. On launch, the system automatically builds its SwiftData container and seeds a mock patient schedule (including Catherine Hartley, Maria Santos, and Robert Chen) so you can review patient dashboards immediately.
2. Navigate to **Settings** $\rightarrow$ **Live SMART / EHR Import**.
3. Select the **SMART R4 Sandbox** preset. This will prefill the default FHIR sandbox URL and public Client ID.
4. Tap **Connect SMART Sandbox**. A sandboxed authorization prompt will appear in a system-controlled sheet. Follow the login steps below to authenticate and sync.

---

## 2. Sandbox Authentication Credentials

The **SMART R4 Sandbox** does not require custom client registration or secret keys. When the OAuth sign-in sheet is presented, please select or enter the following sandbox patient profiles to test data synchronization:

* **EHR Sandbox Patient ID:** `8148e653-ec52-4fc8-9f1a-b6b8b0e8c0fa` (Default test sandbox patient)
* **Preset Sandbox User:** 
  * If the sandbox prompts for user credentials, you can use any public SMART sandbox credentials (such as the default developer credentials provided on the SMART Health IT sandbox login page) or proceed with anonymous sandbox access.
* **Manual Bearer Token Fallback:** If the public sandbox authorization endpoints are offline during your review, you can paste any valid R4-compliant access token into the "Manual Access Token" field in Settings and tap "Apply Token" to run imports immediately.

---

## 3. Reviewing On-Device AI & RAG

OpenClinic does not connect to external LLM services (such as OpenAI, Anthropic, or proprietary APIs). All semantic search indexing, hybrid query merging, and note generation run locally:

* **Hardware Compatibility:** Local intelligence leverages Apple's `FoundationModels` framework when executed on compatible Apple Silicon hardware running iOS 26.2+, macOS 26.2+, or visionOS 26.2+.
* **Reviewing Offline:** You can verify the offline safety boundary by turning off Wi-Fi/Cellular on the review device. Navigate to the **Intelligence** tab and ask a clinical question (e.g. "What medications is Maria Santos currently taking?"). The RAG pipeline will run, perform token budgeting, and generate a verified, locally-sourced answer.
* **Verification Checks:** The intelligence response will display a confidence level shield and granular warnings (e.g. if the answer contains unsourced numbers, or if data isolation filters were active).

---

## 4. Required Device System Permissions

The application requests access to the following hardware APIs under the corresponding workflows:

| Permission | Purpose | Trigger Event |
|---|---|---|
| **Microphone & Speech Recognition** | Used to transcribe raw clinician audio dictations in the encounter editor. | Tapping "Start Dictation" inside `ClinicalExamView`. |
| **Camera** | Used to capture clinical dermatological photos of lesions. | Tapping "Camera" inside the Patient Chart photo section. |
| **Photo Library** | Used to import prior lesion photos to compare progress timelines. | Tapping "Import Photo" inside the Patient Chart photo section. |

---

## 5. Clean Reset Procedure

To reset the reviewer state back to a clean launch configuration:
1. Open **Settings** inside the application.
2. Tap the database reset or wipe configuration options, or delete the app from the device.
3. This wipes the SwiftData container and Keychain credentials, restoring the default seeded agenda list on the next install.
