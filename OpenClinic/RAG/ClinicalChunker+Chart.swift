//
//  ClinicalChunker+Chart.swift
//  OpenClinic
//
//  Chunks for the structured chart rows: problems, allergies, observations,
//  encounters, procedures, immunizations, reports and documents. These are the
//  rows a SMART on FHIR import fills, so an imported record is searchable the
//  same way a locally written note is.
//
//  Each chunk is a short list of dated facts in plain sentences. Rows the source
//  no longer returns are left out.
//

import Foundation

extension ClinicalChunker {
    /// Lines per chunk for list-shaped sections. Small enough that a retrieved chunk fits the
    /// on-device model's context beside several others.
    private static let linesPerChunk = 18

    static func chunkChart(for patient: PatientProfile) -> [ClinicalChunk] {
        var chunks: [ClinicalChunk] = []

        chunks += problemChunks(patient)
        chunks += allergyChunks(patient)
        chunks += observationChunks(patient)
        chunks += encounterChunks(patient)
        chunks += procedureChunks(patient)
        chunks += immunizationChunks(patient)
        chunks += reportChunks(patient)
        chunks += documentChunks(patient)

        return chunks
    }

    // MARK: - Sections

    private static func problemChunks(_ patient: PatientProfile) -> [ClinicalChunk] {
        let problems = (patient.problems ?? [])
            .filter { !$0.isRemovedAtSource }
            .sorted { ($0.sortDate ?? .distantPast) > ($1.sortDate ?? .distantPast) }
        let lines = problems.map { problem -> String in
            var parts = ["\(problem.display): \(problem.clinicalStatus)"]
            if let code = problem.code { parts.append("code \(code)") }
            if let onset = problem.onsetDate { parts.append("onset \(day(onset))") }
            if let abatement = problem.abatementDate { parts.append("resolved \(day(abatement))") }
            return parts.joined(separator: ", ")
        }
        return listChunks(lines, heading: "Problem list", patient: patient, source: .problem, category: .problemList, date: nil)
    }

    private static func allergyChunks(_ patient: PatientProfile) -> [ClinicalChunk] {
        let allergies = (patient.chartAllergies ?? []).filter { !$0.isRemovedAtSource }
        guard !allergies.isEmpty else { return [] }
        let lines = allergies.map { allergy -> String in
            if allergy.isNoKnownAllergyAssertion { return "No known allergies recorded" }
            var parts = [allergy.substance]
            if let status = allergy.clinicalStatus { parts.append(status) }
            if let criticality = allergy.criticality { parts.append("criticality \(criticality)") }
            if !allergy.reactions.isEmpty { parts.append("reactions: \(allergy.reactions.joined(separator: ", "))") }
            if let recorded = allergy.recordedDate { parts.append("recorded \(day(recorded))") }
            return parts.joined(separator: ", ")
        }
        return listChunks(lines, heading: "Allergies and intolerances", patient: patient, source: .allergy, category: .allergiesAndRisks, date: nil)
    }

    /// Observations read best by visit: one chunk per day and category, newest first.
    private static func observationChunks(_ patient: PatientProfile) -> [ClinicalChunk] {
        let observations = (patient.observations ?? []).filter { !$0.isRemovedAtSource }
        guard !observations.isEmpty else { return [] }

        struct Group: Hashable {
            let category: String
            let dayStart: Date?
        }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: observations) { observation in
            Group(category: observation.category, dayStart: observation.effectiveDate.map { calendar.startOfDay(for: $0) })
        }

        var chunks: [ClinicalChunk] = []
        let orderedGroups = grouped.keys.sorted { lhs, rhs in
            let left = lhs.dayStart ?? .distantPast
            let right = rhs.dayStart ?? .distantPast
            return left != right ? left > right : lhs.category < rhs.category
        }
        for group in orderedGroups {
            let rows = (grouped[group] ?? []).sorted { $0.display < $1.display }
            let lines = rows.map { observation -> String in
                var line = "\(observation.display): \(observation.displayValue)"
                if let flag = ObservationFormatting.interpretationLabel(observation.interpretation) { line += " (\(flag))" }
                if let range = observation.referenceRange { line += ", reference \(range)" }
                return line
            }
            let (heading, category) = observationHeading(group.category)
            let dated = group.dayStart.map { "\(heading) on \(day($0))" } ?? "\(heading), date not recorded"
            chunks += listChunks(lines, heading: dated, patient: patient, source: .observation, category: category, date: group.dayStart)
        }
        return chunks
    }

    private static func observationHeading(_ category: String) -> (String, ClinicalCategory) {
        switch category {
        case "vital-signs": return ("Vital signs", .vitalSigns)
        case "laboratory": return ("Laboratory results", .laboratory)
        case "social-history": return ("Social history", .socialHistory)
        case "survey": return ("Survey responses", .socialHistory)
        case "exam": return ("Exam observations", .examFindings)
        default: return ("Observations", .examFindings)
        }
    }

    private static func encounterChunks(_ patient: PatientProfile) -> [ClinicalChunk] {
        let encounters = (patient.encounters ?? [])
            .filter { !$0.isRemovedAtSource }
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
        let lines = encounters.map { encounter -> String in
            var parts: [String] = []
            parts.append(encounter.startDate.map { day($0) } ?? "Date not recorded")
            parts.append(encounter.typeDisplay)
            if let classDisplay = encounter.classDisplay { parts.append(classDisplay) }
            if let reason = encounter.reason { parts.append("reason: \(reason)") }
            if let practitioner = encounter.practitioner { parts.append("with \(practitioner)") }
            if let provider = encounter.serviceProvider { parts.append("at \(provider)") }
            return parts.joined(separator: ", ")
        }
        return listChunks(lines, heading: "Encounter history", patient: patient, source: .encounter, category: .encounterHistory, date: nil)
    }

    private static func procedureChunks(_ patient: PatientProfile) -> [ClinicalChunk] {
        let procedures = (patient.procedures ?? [])
            .filter { !$0.isRemovedAtSource }
            .sorted { ($0.performedStart ?? .distantPast) > ($1.performedStart ?? .distantPast) }
        let lines = procedures.map { procedure -> String in
            var parts = [procedure.performedStart.map { day($0) } ?? "Date not recorded", procedure.display, procedure.status]
            if let reason = procedure.reason { parts.append("reason: \(reason)") }
            return parts.joined(separator: ", ")
        }
        return listChunks(lines, heading: "Procedures", patient: patient, source: .procedure, category: .procedures, date: nil)
    }

    private static func immunizationChunks(_ patient: PatientProfile) -> [ClinicalChunk] {
        let immunizations = (patient.immunizations ?? [])
            .filter { !$0.isRemovedAtSource }
            .sorted { ($0.occurrenceDate ?? .distantPast) > ($1.occurrenceDate ?? .distantPast) }
        let lines = immunizations.map { immunization in
            "\(immunization.occurrenceDate.map { day($0) } ?? "Date not recorded"), \(immunization.vaccine), \(immunization.status)"
        }
        return listChunks(lines, heading: "Immunizations", patient: patient, source: .immunization, category: .immunizations, date: nil)
    }

    /// A report lists its results with their values when the result observations were imported.
    private static func reportChunks(_ patient: PatientProfile) -> [ClinicalChunk] {
        let reports = (patient.diagnosticReports ?? [])
            .filter { !$0.isRemovedAtSource }
            .sorted { ($0.effectiveDate ?? .distantPast) > ($1.effectiveDate ?? .distantPast) }
        guard !reports.isEmpty else { return [] }

        var observationsByReference: [String: ChartObservation] = [:]
        for observation in patient.observations ?? [] where !observation.isRemovedAtSource {
            if let id = observation.sourceRecordIdentifier {
                observationsByReference["Observation/\(id)"] = observation
            }
        }

        var chunks: [ClinicalChunk] = []
        for report in reports {
            var lines: [String] = ["Status: \(report.status)"]
            if let conclusion = report.conclusion, !conclusion.isEmpty { lines.append("Conclusion: \(conclusion)") }
            for reference in report.resultReferences {
                if let observation = observationsByReference[reference] {
                    lines.append("\(observation.display): \(observation.displayValue)")
                }
            }
            if let text = report.presentedText, !text.isEmpty { lines.append(text) }
            let heading = "\(report.display) report" + (report.effectiveDate.map { " on \(day($0))" } ?? "")
            chunks += listChunks(lines, heading: heading, patient: patient, source: .diagnosticReport, category: .reports, date: report.effectiveDate)
        }
        return chunks
    }

    private static func documentChunks(_ patient: PatientProfile) -> [ClinicalChunk] {
        let documents = (patient.documents ?? [])
            .filter { !$0.isRemovedAtSource }
            .sorted { ($0.documentDate ?? .distantPast) > ($1.documentDate ?? .distantPast) }

        var chunks: [ClinicalChunk] = []
        for document in documents {
            guard let text = document.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { continue }
            var heading = document.typeDisplay
            if let date = document.documentDate { heading += " on \(day(date))" }
            if let author = document.author { heading += " by \(author)" }

            let words = text.split(whereSeparator: \.isWhitespace)
            let wordsPerChunk = 280
            var start = words.startIndex
            var index = 0
            while start < words.endIndex {
                let end = min(start + wordsPerChunk, words.endIndex)
                let content = words[start..<end].joined(separator: " ")
                chunks.append(makeChunk(
                    content: content, heading: heading, index: index, patient: patient,
                    source: .document, category: .documents, date: document.documentDate
                ))
                index += 1
                start = end
            }
        }
        return chunks
    }

    // MARK: - Helpers

    /// Splits a list into chunks, each headed by what the list is so a chunk reads on its own.
    private static func listChunks(
        _ lines: [String],
        heading: String,
        patient: PatientProfile,
        source: ClinicalSourceType,
        category: ClinicalCategory,
        date: Date?
    ) -> [ClinicalChunk] {
        guard !lines.isEmpty else { return [] }
        var chunks: [ClinicalChunk] = []
        var start = 0
        var index = 0
        while start < lines.count {
            let end = min(start + linesPerChunk, lines.count)
            let content = "\(heading):\n" + lines[start..<end].joined(separator: "\n")
            chunks.append(makeChunk(content: content, heading: heading, index: index, patient: patient, source: source, category: category, date: date))
            index += 1
            start = end
        }
        return chunks
    }

    private static func makeChunk(
        content: String,
        heading: String,
        index: Int,
        patient: PatientProfile,
        source: ClinicalSourceType,
        category: ClinicalCategory,
        date: Date?
    ) -> ClinicalChunk {
        ClinicalChunk(
            patientId: patient.id,
            content: content,
            contextualPrefix: "[\(patient.fullName)] [\(heading)]",
            metadata: ChunkMetadata(
                chunkIndex: index,
                sourceType: source,
                sectionTitle: heading,
                dateRecorded: date,
                clinicalCategory: category,
                patientName: patient.fullName,
                wordCount: content.split(whereSeparator: \.isWhitespace).count
            )
        )
    }

    private static func day(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}
