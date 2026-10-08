//
//  DeviceSelfCheck.swift
//  OpenClinic
//
//  A debug-only check a build can run on a phone or a simulator with nobody
//  tapping: launch with `-OpenClinicSelfCheck` and read the lines that start
//  with SELFCHECK on standard output. It exercises the store, the launch index
//  sync, a computed panel answer, a live read of one synthetic patient from the
//  open sandbox (into a store in memory, so the device's chart store is not
//  touched) and, where Apple Intelligence is ready, three patient questions and
//  one dictated note, each reported with who wrote the text.
//
//  Lines hold counts, timings and demo record numbers. Nothing from a chart.
//

#if DEBUG

import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
enum DeviceSelfCheck {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-OpenClinicSelfCheck")
    }

    private static var passed = 0
    private static var failed = 0

    private static func line(_ text: String) {
        print("SELFCHECK \(text)")
        fflush(stdout)
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String) {
        if ok { passed += 1 } else { failed += 1 }
        line("\(ok ? "ok  " : "FAIL") \(name): \(detail)")
    }

    private static func milliseconds(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }

    static func run(container: ModelContainer, storeIssue: String?, launchSync: ClinicalRAGService.IndexSyncSummary?) async {
        passed = 0
        failed = 0
        let context = container.mainContext

        // A phone that locks itself suspends the app, and the check then looks hung. On 2026-10-07
        // two runs stopped that way part of the way through. The screen stays awake until the check ends.
        #if canImport(UIKit) && !os(visionOS)
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        #endif

        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        line("device: \(machine), \(ProcessInfo.processInfo.operatingSystemVersionString)")

        // 1. The store opened, and the demo panel is in it.
        let patients = (try? context.fetch(FetchDescriptor<PatientProfile>())) ?? []
        let demo = patients.filter { $0.medicalRecordNumber.hasPrefix("OC-") }
        check("store", storeIssue == nil && demo.count == 10, "\(patients.count) patients, \(demo.count) of the demo panel, store issue: \(storeIssue == nil ? "none" : "yes")")

        // 2. The launch index sync.
        if let sync = launchSync {
            check("index", sync.chunksInIndex > 0,
                  "\(sync.chunksInIndex) chunks; \(sync.chunksEmbedded) embedded, \(sync.vectorsReused) reused; \(sync.patientsUnchanged) patients unchanged, \(sync.patientsUpdated) updated; \(Int(sync.milliseconds)) ms")
        } else {
            check("index", false, "the launch sync did not report")
        }

        // 3. A panel question with one right answer, computed from chart facts.
        do {
            let start = Date()
            let answer = try await ClinicalIntelligenceService().answerPanelQuestion("Which patients have melanoma history?", modelContext: context)
            if case .computed(let result) = answer {
                // Only demo record numbers are printed. An imported chart on this device is counted, not named.
                let demoMatches = result.matchedMRNs.filter { $0.hasPrefix("OC-") }
                check("panel", demoMatches == ["OC-1003"],
                      "demo matches \(demoMatches.sorted()); \(result.matchedMRNs.count) matched and \(result.relatedMRNs.count) related of \(result.panelSize); \(milliseconds(since: start)) ms")
            } else {
                check("panel", false, "the question was sent to the model instead of being computed")
            }
        } catch {
            check("panel", false, "threw \(type(of: error))")
        }

        // 4. A live read of one synthetic patient, mapped and saved to a store in memory.
        do {
            let start = Date()
            guard let base = URL(string: "https://r4.smarthealthit.org") else { throw URLError(.badURL) }
            let client = FHIRR4Client(baseURL: base, session: URLSession(configuration: .ephemeral))
            let first = try await client.search("Patient", parameters: [URLQueryItem(name: "_count", value: "1")])
            guard let patientID = first.resources.first?.id else { throw URLError(.badServerResponse) }
            let fetched = try await FHIRR4ChartFetcher(client: client).fetchChart(patientID: patientID)
            let scratch = ModelContext(try OpenClinicSchema.makeInMemoryContainer())
            let summary = try ChartImportApplier(context: scratch).apply(fetched.chart, sourceResources: fetched.rawResources)
            check("import", summary.sourceResourceCount > 0 && fetched.chart.failedTypes.isEmpty,
                  "\(summary.sourceResourceCount) resources, \(summary.totalReceived) chart facts, \(fetched.chart.failedTypes.count) types failed, \(summary.warnings.count) warnings; \(milliseconds(since: start)) ms")
        } catch {
            check("import", false, "\(type(of: error))")
        }

        // 5. Answers from the on-device model, where it is ready. The model declines some questions,
        //    and the app then lists chart rows instead, so each answer is reported with who wrote it.
        let modelState = modelAvailability()
        line("model: \(modelState.description)")
        if modelState.isReady, let chen = demo.first(where: { $0.medicalRecordNumber == "OC-1003" }) {
            let questions = [
                "What medications is this patient taking?",
                "Summarize the plan from the most recent visit.",
                "When is the next appointment and what is it for?",
            ]
            var writtenByModel = 0
            for question in questions {
                let start = Date()
                do {
                    let answer = try await ClinicalIntelligenceService().answerPatientQuestion(query: question, modelContext: context, patient: chen)
                    switch answer.origin {
                    case .model:
                        writtenByModel += 1
                        line("     answer: written by the model, \(answer.text.count) characters, \(milliseconds(since: start)) ms | \(question)")
                    case .chartListing(let reason), .keywordRules(let reason):
                        line("     answer: listed by the app, \(answer.text.count) characters, \(milliseconds(since: start)) ms | \(question) | \(reason)")
                    }
                } catch {
                    line("     answer: threw \(type(of: error)) | \(question)")
                }
            }
            check("generation", writtenByModel > 0, "the model wrote \(writtenByModel) of \(questions.count) answers")

            // 6. A visit note drafted from a dictation.
            let dictation = "Patient returns for psoriasis follow up. Plaques on both elbows improved about fifty percent on methotrexate fifteen milligrams weekly. No nausea, no mouth sores. Exam shows thin pink plaques on bilateral elbows with minimal scale. Continue methotrexate, check CBC and CMP today, return in twelve weeks."
            do {
                let start = Date()
                let draft = try await ClinicalIntelligenceService().draftNote(from: dictation, patient: chen, selectedAnatomy: nil)
                let namesTheDrug = draft.note.impressionsAndPlan.localizedCaseInsensitiveContains("methotrexate")
                switch draft.origin {
                case .model:
                    check("note", namesTheDrug, "drafted by the model, plan names methotrexate: \(namesTheDrug), \(draft.note.recommendedOrders.count) orders; \(milliseconds(since: start)) ms")
                case .keywordRules(let reason), .chartListing(let reason):
                    check("note", false, "filled in by keyword rules; \(milliseconds(since: start)) ms | \(reason)")
                }
            } catch {
                check("note", false, "threw \(type(of: error))")
            }
        } else {
            line("skip generation: the on-device model is not ready here")
        }

        line("DONE passed=\(passed) failed=\(failed)")
    }

    private static func modelAvailability() -> (isReady: Bool, description: String) {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            switch SystemLanguageModel(useCase: .general).availability {
            case .available:
                return (true, "Apple Intelligence available")
            case .unavailable(.appleIntelligenceNotEnabled):
                return (false, "Apple Intelligence is turned off")
            case .unavailable(.deviceNotEligible):
                return (false, "this device is not eligible for Apple Intelligence")
            case .unavailable(.modelNotReady):
                return (false, "the on-device model is not ready yet")
            @unknown default:
                return (false, "Apple Intelligence availability unknown")
            }
        }
        #endif
        return (false, "FoundationModels is not in this build")
    }
}

#endif
