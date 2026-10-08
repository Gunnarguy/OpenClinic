# OpenClinic

## Verify
./Scripts/verify.sh          # unit tests on the macOS host, then an iOS Simulator build
./Scripts/verify.sh tests    # unit tests only
./Scripts/verify.sh build    # iOS Simulator build only; prints the .app path for simctl install
Do not report done until this exits 0 and you have read the output.
The script refuses to run with iCloud conflict copies in the tree or under 4 GB free disk.
Build products go to ~/Library/Developer/Xcode/DerivedData/OpenClinic-verify, never inside the repository.

## What this is
A clinical workspace prototype (iPhone, iPad, Mac) on synthetic data: schedule, charting, encounter notes,
full-record FHIR R4 import (SMART on FHIR, or the open sandbox with no sign-in), and on-device chart questions.
It is a portfolio proof-of-concept. The word for it everywhere is "prototype". It has never held real patient
data and is not cleared for clinical use. This file is public with the repository: keep private notes out of it.

## Rules
- Every claim in README, ARCHITECTURE, ROADMAP and the case study must be true of the code at that commit.
  When the code and a document disagree, fix the document or the code in the same change.
- Nothing in a chart view is invented at render time. A value on screen comes from a stored model or from the
  demo fixture. Hardcoded or hash-derived clinical values are defects.
- The demo panel lives in OpenClinic/Resources/Demo/DemoPanel.json and is seeded by DemoDataSeeder. It must
  stay clinically coherent: ages match dates of birth, today's notes agree with the history, zones and ICD-10
  codes match the text. DemoPanelTests checks this.
- The problem list a chart shows is ProblemList.entries: charted problems (ChartProblem), then diagnoses only a
  note names, marked as such. Counts on the patient lists come from the same function. ProblemListTests holds it.
- A record import re-indexes only the imported patient (ClinicalRAGService.indexPatient). A full reindex is for
  launch, "Reindex" in Settings and a demo reset.
- Unit tests never call a language model: ClinicalIntelligenceService.languageModelEnabled is false in tests.
- A panel question with one correct answer ("which patients ...") is computed by CohortEngine from chart
  facts, never written by the language model. A question the parser does not fully understand returns nil
  and goes to the model, and the UI labels that answer as unverified. PanelQuestionEvalTests holds the
  hand-written expected answers; add a case there with every new kind of question.
- An import never deletes and never invents. A row the server stops returning is marked isRemovedAtSource.
  A resource type whose search failed or was truncated is left as it was (ImportedChart.failedTypes and
  truncatedTypes). A missing value shows as "Not recorded at source", not a guess. Imported times are the
  server's. Every imported row keeps its FHIRResourceRecord.
- Every SwiftData container is built from OpenClinicSchema, and the app and App Intents share
  AppStore.shared. A second container with a partial schema on the same file can drop tables.
- A store that fails to open is moved aside by StoreBootstrap, never deleted.
- Never log patient names, MRNs or note text in plain text. Use os.Logger privacy markers. Never log or show a
  token endpoint body or a FHIR response body. The access log (AuditEvent) holds identifiers, never content.
- The FHIR layer in OpenClinic/Interop/FHIR/R4 imports only Foundation and os and must typecheck alone:
  xcrun swiftc -typecheck -swift-version 5 OpenClinic/Interop/FHIR/R4/*.swift
- New value types and pure logic are declared nonisolated (the target's default isolation is MainActor).
- Info.plist, OpenClinic.entitlements and project.pbxproj change only when Gunnar names the file.
- Commits go to main, no branches left over, no co-author trailers. Commit and push only when asked.

## Machine constraints
- One xcodebuild at a time. This Mac has 18 GB of memory and other sessions build on it.
- A booted simulator holds about 3 GB, and on-device model generation in the simulator holds more.
  On 2026-10-07 swap grew from about 5 GB to 15.6 GB and free disk fell to 147 MiB while a simulator, a
  test run and another session's tests overlapped. Shut the simulator down when a check is finished.
- OpenClinic's own simulator is "OpenClinic review iPad" (iPad Pro 13-inch M5, iOS 27.0, no keys in it).
  Simulators on this Mac get deleted without notice (it happened mid-session on 2026-10-07), so check
  `xcrun simctl list devices` before naming a UDID and make the device again when it is gone.
- Taps sent to the simulator while it indexes arrive late or not at all. The main thread is idle then
  (2.3% busy in an 8 s sample on 2026-10-07); Core ML inference on the CPU starves the simulator. Wait for
  "Reindex complete" in the log before driving the UI.
- Do not edit a Swift file while verify.sh is compiling. On 2026-10-07 a file saved mid-build produced a
  compile error that was not in the tree a minute later.

## OpenIntelligence engine
The retrieval code under OpenClinic/RAG is an adaptation of OpenIntelligence's, kept here. Embedding the engine
package itself (product OpenIntelligenceEngine, API OIEngine) needs changes in the OpenIntelligence repository
first, and a package reference in project.pbxproj, which Gunnar has to name. Do not edit OpenIntelligence from
an OpenClinic session.
