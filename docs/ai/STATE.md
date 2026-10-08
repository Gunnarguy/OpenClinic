# Current State

Updated: 2026-10-08
Branch/worktree: main at ~/Documents/GitHub/OpenClinic
Last verified commit: 216df62 (pushed 2026-10-08); the commit that carries this file adds the Mac network entitlement and the refresh-token scope, verified the same day: `./Scripts/verify.sh` 266 tests, 0 failures, 0 warnings

## Objective
Close the open points left at 2aac3b3: launch re-indexing, the unused HealthKit entitlement, SMART sign-in and a
physical device unverified, the FHIR layer's open points, and text that did not say who wrote it. Embedding the
OpenIntelligence engine package is a separate, blocked item (see Blockers).

## Status
Committed and pushed to `main` on 2026-10-08 at Gunnar's word. In progress the same day, also at his word:
embedding the OpenIntelligence engine package (see Blockers).

## Completed
- Launch index sync (`ClinicalRAGService.syncIndex`, `ClinicalIndexSync.plan`): only changed chart text is embedded.
- HealthKit entitlement and purpose strings removed; `verify.sh` no longer overrides the entitlements file.
- Who wrote the text: `AnswerOrigin` on every answer, `AnswerDialog` for Shortcuts, `SavedNoteOrigin` for a saved
  note; the AI badge only on model text; a panel answer is all model or all app text.
- Prompts the on-device model answers (a record and a question, or a dictation alone, no clinical role), one
  time limit per model call (`withModelTimeLimit`).
- `DictationSorter`: the note drafted without the model is the dictation's own sentences, sorted by whole-word
  rules, with the whole dictation as its history; the template findings, plans and orders the keyword rules
  used to add are gone.
- A listing for a patient holds that patient's rows only (it fell back to every patient's rows when there were none).
- FHIR: redirects and paging links stay on the server, a relative link is read against its page, partial dates
  keep their precision or are reported, deceased patients, no date of birth means no age, government numbers
  removed from the stored Patient resource (identifiers anywhere in it, equal values, narrative text), a chart
  stored under another spelling of the server address is found again, and a one-time repair
  (`ChartImportApplier.repairChartsFromEarlierVersions`) applies both to charts an earlier version imported.
- SMART: the callback's `state` is required, a token request follows no redirect, scopes cover every imported type.
- `Scripts/verify.sh` modes `tests`, `build`, `live`, `device`; `OpenClinic/Demo/DeviceSelfCheck.swift`.
- The Mac target has the outgoing-network entitlement, so the Mac build reaches a FHIR server; `verify.sh live`
  runs inside that sandbox. A sign-in asks for `offline_access` where the server offers refresh tokens.
- `AGENTS.md`, `.agents/` and `.codex/` are ignored: another agent tool wrote an `AGENTS.md` copy of `CLAUDE.md`
  here on 2026-10-08, and `CLAUDE.md` stays the one instruction file.

## Active Constraints
- The word for the app is "prototype". Synthetic data only. This repository is public.
- `Info.plist`, `OpenClinic.entitlements` and `project.pbxproj` change only when Gunnar names the file.
- One `xcodebuild` at a time; never edit a Swift file while `verify.sh` compiles.
- Simulators on this Mac are deleted without notice. Run `xcrun simctl list devices` before naming a UDID.
- Do not edit the OpenIntelligence repository from here without Gunnar's `PROCEED: IMPLEMENT` in that repository's terms.

## Working Set
- `OpenClinic/AI/ClinicalIntelligenceService.swift`: answers, origins, prompts, time limit.
- `OpenClinic/AI/DictationSorter.swift`, `OpenClinic/AI/VisitNoteText.swift`: the two note forms without a structured answer.
- `OpenClinic/RAG/ClinicalRAGService.swift`, `ClinicalIndexSync.swift`, `ClinicalVectorStore.swift`, `ClinicalFTSService.swift`: index sync.
- `OpenClinic/Interop/FHIR/R4/FHIRR4Client.swift`, `FHIRR4ChartMapper.swift`; `OpenClinic/Interop/Import/ChartImportApplier.swift`.
- `OpenClinic/Interop/SMART/SMARTSession.swift`; `OpenClinicTests/Interop/SMARTLiveSignInTests.swift` (opt-in).
- `OpenClinic/Demo/DeviceSelfCheck.swift`, `Scripts/verify.sh`.
- `ROADMAP.md` section 3: every known limitation.

## Verification
- `./Scripts/verify.sh` -> `PANEL EVAL: 31/31 set-exact`, `Executed 266 tests, with 2 tests skipped and 0 failures`,
  `test build warnings: 0`, `iOS Simulator build succeeded, warnings: 0`, `verify: OK`; the 2 skipped are the opt-in live SMART tests (2026-10-08).
- `./Scripts/verify.sh live` -> `sign-in ok | patient in token: true | refresh token issued: true | resources read
  with the token: 547 | types failed: 0 | refresh ok: true`; a wrong PKCE verifier refused with 401; `verify: OK`
  (2026-10-08; run again the same day with the Mac sandbox on, 394 resources, `verify: OK`).
- `xcrun swiftc -typecheck -swift-version 5 OpenClinic/Interop/FHIR/R4/*.swift` -> no output, exit 0.
- Debug Mac build launched with `-OpenClinicSelfCheck` on the final tree, 2026-10-08 (macOS 27.0, the Mac's
  on-device model; the build `verify.sh live` leaves, which has the app sandbox off): `DONE passed=6 failed=0`;
  index sync of an unchanged 291-chunk index 776 ms; live import of one sandbox patient, 547 resources in 5.0 s;
  `the model wrote 3 of 3 answers` (4.6 to 13.0 s each); `note: drafted by the model`.
- iOS 27.0 Simulator self-check, 2026-10-07, before the last two batches of edits: `DONE passed=6 failed=0`, the
  model wrote 3 of 3 answers and drafted the note; index sync of an unchanged 615-chunk index 1,074 ms.
- iPhone 16 Pro Max, 2026-10-07, old prompts: store, index (291 chunks, 3,154 ms first, 293 to 474 ms later),
  panel and live import passed; the model refused 3 of 3 patient questions.
- Not verified: the new prompts on a physical device. `./Scripts/verify.sh device` on 2026-10-08 built, signed
  and installed (with the new entitlement too), then failed at launch because the iPhone was locked.

## Blockers / Unknowns
- New prompts on the iPhone. Check: unlock the phone, keep it awake, run `./Scripts/verify.sh device`; it must end
  with `SELFCHECK DONE ... failed=0` and a `generation` line that says the model wrote the answers.
- Embedding the OpenIntelligence engine package needs a change in that repository and a package reference in
  `project.pbxproj`. Check: `grep -n OpenIntelligenceEngine OpenClinic.xcodeproj/project.pbxproj` prints nothing
  until that is done.
- The last round of fixes (the whole-word rules, the repair pass, identifiers anywhere in the Patient resource)
  is covered by tests and has had no independent review. Check: run the reviewer agent on `git diff 2aac3b3 216df62`.

## Exact Next Action
Embed the OpenIntelligence engine: confirm the engine commit OpenClinic is to pin exists on GitHub
(`git ls-remote https://github.com/Gunnarguy/OpenIntelligence | grep openclinic`), then add the package reference to
`OpenClinic.xcodeproj/project.pbxproj` (Gunnar named the file on 2026-10-08) and run `./Scripts/verify.sh`.
