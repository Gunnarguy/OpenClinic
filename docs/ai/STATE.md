# Current State

Updated: 2026-10-07
Branch/worktree: main at ~/Documents/GitHub/OpenClinic
Last verified commit: 50b1d02 (`./Scripts/verify.sh` passed on a tree whose app, tests and script are byte-identical to this commit; only documents changed after the run)

## Objective
Make OpenClinic a complete, credible clinical-workspace prototype on synthetic data: a coherent demo panel,
full-record FHIR R4 import (SMART on FHIR and the open sandbox), chart questions answered from chart facts,
and engineering that holds up to review (one verify command, tests for every rule, documents that match the code).

## Status
Shipped to `main` on 2026-10-07. No objective is in progress.

## Completed
- Demo panel from one fixture (`OpenClinic/Resources/Demo/DemoPanel.json`, version 3): 10 patients with coded
  problems, allergies, vital signs, labs, notes and today's schedule, kept coherent by `DemoPanelTests` and
  `DemoChartRowsTests`.
- Panel questions with one right answer are computed by `CohortEngine` with evidence per match;
  `PanelQuestionEvalTests` scores 31 questions against hand-written patient sets.
- FHIR R4 read layer (`OpenClinic/Interop/FHIR/R4`, Foundation only) and `ChartImportApplier`: paging, retries,
  token refresh, entered-in-error left out, rows the server stops returning kept and marked, every row linked
  to its stored source resource, an access log.
- Chart: vital signs and results from stored observations, a Record tab, a problem list that merges charted
  problems with diagnoses only a note names (`ProblemList.entries`), a Summary tab cut from 10 blocks to 7.
- Fixed on the last day, each found by measurement: the saved vector index doubled at every launch
  (`ClinicalVectorStore.loadFromDisk` now does nothing once the store has been written); an import re-indexed the
  whole panel (now `ClinicalRAGService.indexPatient`); unit tests called the live language model.

## Active Constraints
- The word for the app is "prototype". Synthetic data only.
- This repository is public. `CLAUDE.md` lists what stays out of committed files.
- `Info.plist`, `OpenClinic.entitlements` and `project.pbxproj` change only when Gunnar names the file.
- One `xcodebuild` at a time; never edit a Swift file while `verify.sh` compiles.
- Simulators on this Mac are deleted without notice. Run `xcrun simctl list devices` before naming a UDID.
- Run `gtimeout 60 git fetch origin` and compare with `origin/main` before committing. On 2026-10-07 this checkout
  was 2 documentation commits behind the remote and the work had to be rebased onto them.
- `.git/stale-rebase-merge-2026-07-10` is the bookkeeping folder of a rebase from 2026-07-10 whose 8 commits are
  all in history. It was renamed from `.git/rebase-merge` on 2026-10-07 so Git stops reporting a rebase in
  progress. Renaming it back restores the old state; deleting it is Gunnar's call.

## Working Set
- `Scripts/verify.sh`: the one verify command.
- `OpenClinic/Models/ClinicalProblemSummary.swift`: `ProblemList.entries`, the problem list every view reads.
- `OpenClinic/Views/PatientDashboardView.swift`: the chart, including the inline decision-support rules.
- `OpenClinic/RAG/ClinicalRAGService.swift`, `ClinicalVectorStore.swift`: indexing and the vector file.
- `OpenClinic/Interop/Import/ChartImportCoordinator.swift`, `ChartImportApplier.swift`: the import path.
- `ROADMAP.md`, section 3: every known limitation, the FHIR layer's open points included.

## Verification
- `./Scripts/verify.sh` -> `PANEL EVAL: 31/31 set-exact`, `Executed 191 tests, with 0 failures`,
  `test build warnings: 0`, `iOS Simulator build succeeded, warnings: 0`, `verify: OK` (2026-10-07).
- `xcrun swiftc -typecheck -swift-version 5 OpenClinic/Interop/FHIR/R4/*.swift` -> no output, exit 0.
- iOS 27.0 Simulator, 2026-10-07: a sandbox patient with 1,426 source resources imported from
  `https://r4.smarthealthit.org` (20 problems, 1,103 observations, 155 encounters); a second import re-indexed
  47 chunks in 7.2 s against 117.8 s for the full reindex before it.
- Not verified: SMART sign-in against a server that needs authorization (needs a person at the sign-in sheet);
  anything on a physical device; the visionOS destination.

## Blockers / Unknowns
- Embedding the OpenIntelligence engine package needs changes in that repository and a package reference in
  `project.pbxproj`. Check: `grep -n OpenIntelligenceEngine OpenClinic.xcodeproj/project.pbxproj` prints nothing
  until that is done.
- Index time on a device is unmeasured. Check: run the app on an iPhone or iPad and read
  `Reindex complete: N chunks ... ms` in Console for subsystem `Gunndamental.OpenClinic`.
- `OpenClinic.entitlements` and `Info.plist` still declare HealthKit although no code uses it, which is why the
  tests need `CODE_SIGN_ENTITLEMENTS=` (already in `verify.sh`). Removing them is Gunnar's call.

## Exact Next Action
None. The previous objective is complete and verified. There is no active objective; ask the user what to pick
up, or take an item from `ROADMAP.md` section 3 (the first two candidates: generated answers checked against
their sources before they are shown, and tested decision-support rules moved out of `PatientDashboardView`).
