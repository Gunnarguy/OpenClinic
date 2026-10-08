# OpenClinic

## Verify
./Scripts/verify.sh          # unit tests on the macOS host, then an iOS Simulator build
./Scripts/verify.sh tests    # unit tests only
./Scripts/verify.sh build    # iOS Simulator build only; prints the .app path for simctl install
./Scripts/verify.sh live     # a real SMART sign-in against launch.smarthealthit.org; needs the network
./Scripts/verify.sh device   # build, install and self-check on a connected, unlocked iPhone or iPad
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
- Launch and App Intents bring the index up to date with ClinicalRAGService.syncIndex, which embeds only text
  that changed (ClinicalIndexSync.plan). A record import re-indexes the imported patient (indexPatient). A full
  rebuild (indexAllData) is for "Reindex" in Settings and a demo reset.
- Text on screen says who wrote it. An answer carries an AnswerOrigin: written by the on-device model, listed
  from chart rows by the app, or (a note) sorted from the dictation by keyword rules. Never label app-written
  text as model-written. A listing for a patient holds that patient's rows only.
- The note the app drafts without the model (DictationSorter) holds the dictation's own sentences and nothing
  else: no template finding, plan or order, nothing from the chart. Its history is the whole dictation, its
  rules match whole words, and it names a diagnosis only by a word the dictation uses in a sentence that does
  not deny it. Its body sites are the one selected and any the dictation names. DictationSorterTests holds it.
  A note whose dictation named no diagnosis is no problem and matches no diagnosis question.
  An answer is all model text or all app text: a multi-pass panel answer whose pass the model declined is
  listed by the app as a whole. A Shortcut's dialog ends with the same line (AnswerDialog), the AI badge and
  the "local_ai" source kind go only on model text, and a saved note takes its kind from SavedNoteOrigin.
- Prompts to the on-device model give it a record and a question, or a dictation alone, and no clinical role.
  The model refused 6 of 6 structured requests framed as a "clinical assistant" and answered 6 of 6 in the
  neutral form (2026-10-07). A structured note is asked for from the dictation only: with the record in the
  prompt it is refused. Check any prompt change with ./Scripts/verify.sh device, not only in the simulator.
- Each model call runs under ClinicalIntelligenceService.withModelTimeLimit, one limit per call. After a
  time-out the patient session is dropped, because the late call may still be running in it.
- A debug build launched with -OpenClinicSelfCheck checks itself and prints SELFCHECK lines
  (OpenClinic/Demo/DeviceSelfCheck.swift). They hold counts, timings and demo record numbers, nothing from a chart.
- The Mac target is sandboxed with no outgoing-network entitlement, so a test that needs the network runs with
  ENABLE_APP_SANDBOX=NO (verify.sh live does this) and the Mac app itself cannot reach a FHIR server.
- Unit tests never call a language model: ClinicalIntelligenceService.languageModelEnabled is false in tests.
- A panel question with one correct answer ("which patients ...") is computed by CohortEngine from chart
  facts, never written by the language model. A question the parser does not fully understand returns nil
  and goes to the model, and the UI labels that answer as unverified. PanelQuestionEvalTests holds the
  hand-written expected answers; add a case there with every new kind of question.
- An import never deletes and never invents. A row the server stops returning is marked isRemovedAtSource.
  A resource type whose search failed or was truncated is left as it was (ImportedChart.failedTypes and
  truncatedTypes) and so is a type with a resource that could not be decoded (unreadableTypes). A missing value
  shows as "Not recorded at source", not a guess. Imported times are the server's. Every imported row keeps its
  FHIRResourceRecord; the stored Patient resource has the values of its government numbers removed.
- A request to a FHIR server follows a redirect or a paging link only when it stays on that server. SMART
  discovery follows the same rule, and a token request (code exchange, refresh) follows no redirect at all.
- A relative paging link is resolved against the page it came on.
- A stored Patient resource holds no government number: not in an identifier anywhere in the resource, not
  in another value that equals one, not in the text of the narrative (resourceForStorage; a number under four
  characters is left in a narrative). Other fields and the narrative's markup are never rewritten. A number
  that is also listed as a government number is never the chart's record number. An import refreshes the
  chart's record number.
- With no date of birth at the source the chart shows no date and no age (PatientProfile.hasKnownBirthDate),
  and no age question matches the patient.
- Launch runs ChartImportApplier.repairChartsFromEarlierVersions until it has finished once on the saved
  store (a UserDefaults flag): it applies the two rules above to charts an earlier version imported.
- The SMART callback's state must be present and equal before its code is used.
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
  "Index sync:" (launch) or "Reindex complete" (Reindex in Settings) in the log before driving the UI.
- Do not edit a Swift file while verify.sh is compiling. On 2026-10-07 a file saved mid-build produced a
  compile error that was not in the tree a minute later.

## OpenIntelligence engine
The retrieval code under OpenClinic/RAG is an adaptation of OpenIntelligence's, kept here. Embedding the engine
package itself (product OpenIntelligenceEngine, API OIEngine) needs changes in the OpenIntelligence repository
first, and a package reference in project.pbxproj, which Gunnar has to name. Do not edit OpenIntelligence from
an OpenClinic session.
