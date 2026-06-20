//
//  ClinicalChunker.swift
//  OpenClinic
//
//  Section-aware clinical note chunking. Splits SwiftData models into
//  embeddable chunks with contextual prefixes for RAG indexing.
//  Max 310 words per chunk, 30-word contextual prefix.
//

import Foundation
import SwiftData
import os

// MARK: - Clinical Chunker

/// Transforms SwiftData clinical models into embeddable ClinicalChunks.
struct ClinicalChunker {
    private static let maxWordsPerChunk = 310

    // MARK: - Patient Profile Chunks

    /// Generate 1 chunk per patient with demographics + allergies + risks + care plan.
    static func chunkPatient(_ patient: PatientProfile) -> [ClinicalChunk] {
        var sections: [String] = []

        sections.append("Patient: \(patient.fullName), \(patient.age) y/o \(patient.gender)")
        sections.append("MRN: \(patient.medicalRecordNumber)")
        if patient.isSmoker { sections.append("Smoking status: Current smoker") }
        if let clinician = patient.primaryClinician { sections.append("Primary clinician: \(clinician)") }
        if let pharmacy = patient.preferredPharmacy { sections.append("Preferred pharmacy: \(pharmacy)") }
        if let blood = patient.bloodType { sections.append("Blood type: \(blood)") }
        if !patient.allergies.isEmpty { sections.append("Allergies: \(patient.allergies.joined(separator: ", "))") }
        if !patient.riskFlags.isEmpty { sections.append("Risk flags: \(patient.riskFlags.joined(separator: ", "))") }
        if let emergency = patient.emergencyContactName {
            sections.append("Emergency contact: \(emergency) \(patient.emergencyContactPhone ?? "")")
        }
        if let carePlan = patient.carePlanSummary, !carePlan.isEmpty {
            sections.append("Care plan: \(carePlan)")
        }

        let content = sections.joined(separator: "\n")
        let prefix = "[\(patient.fullName)] [Demographics & Risk Profile]"

        return [ClinicalChunk(
            patientId: patient.id,
            content: content,
            contextualPrefix: prefix,
            metadata: ChunkMetadata(
                chunkIndex: 0,
                sourceType: .patientProfile,
                sectionTitle: "Demographics & Risk Profile",
                dateRecorded: nil,
                clinicalCategory: .demographics,
                patientName: patient.fullName,
                wordCount: content.split(separator: " ").count
            )
        )]
    }

    // MARK: - Clinical Record Chunks

    /// Section-aware splitting: each note section (CC/HPI, ROS, Exam, A&P, etc.) becomes its own chunk.
    static func chunkRecord(_ record: LocalClinicalRecord, patient: PatientProfile) -> [ClinicalChunk] {
        let dateStr = record.dateRecorded.formatted(date: .abbreviated, time: .omitted)
        var chunks: [ClinicalChunk] = []
        var chunkIndex = 0

        // Helper to create a chunk from a section
        func addSection(content: String, sectionTitle: String, category: ClinicalCategory) {
            let newChunks = createSectionChunks(
                content: content,
                sectionTitle: sectionTitle,
                category: category,
                dateRecorded: record.dateRecorded,
                patientId: patient.id,
                patientFullName: patient.fullName,
                dateStr: dateStr,
                startIndex: chunkIndex
            )
            chunks.append(contentsOf: newChunks)
            chunkIndex += newChunks.count
        }

        // Condition header
        addSection(
            content: "\(record.conditionName) — \(record.status)\(record.severity.map { " | Severity: \($0)" } ?? "")\(record.visitType.map { " | Visit: \($0)" } ?? "")",
            sectionTitle: "Condition",
            category: .fullRecord
        )

        // CC/HPI
        if let ccHPI = record.ccHPI {
            addSection(content: ccHPI, sectionTitle: "Chief Complaint & HPI", category: .chiefComplaint)
        }

        // Review of Systems
        if let ros = record.reviewOfSystems {
            addSection(content: ros, sectionTitle: "Review of Systems", category: .reviewOfSystems)
        }

        // Exam Findings
        if let exam = record.examFindings {
            addSection(content: exam, sectionTitle: "Examination Findings", category: .examFindings)
        }

        // Impressions & Plan
        if let plan = record.impressionsAndPlan {
            addSection(content: plan, sectionTitle: "Assessment & Plan", category: .assessmentAndPlan)
        }

        // Patient Instructions
        if let instructions = record.patientInstructions {
            addSection(content: instructions, sectionTitle: "Patient Instructions", category: .patientInstructions)
        }

        // Follow-Up
        if let followUp = record.followUpPlan {
            addSection(content: followUp, sectionTitle: "Follow-Up Plan", category: .followUp)
        }

        // Orders
        if let orders = record.recommendedOrders, !orders.isEmpty {
            addSection(content: orders.joined(separator: "\n"), sectionTitle: "Recommended Orders", category: .orders)
        }

        // Care Plan Summary
        if let care = record.carePlanSummary {
            addSection(content: care, sectionTitle: "Care Plan Summary", category: .carePlan)
        }

        // Anatomical Zones
        if let zones = record.affectedAnatomicalZones, !zones.isEmpty {
            addSection(content: "Affected zones: \(zones.joined(separator: ", "))", sectionTitle: "Anatomical Zones", category: .examFindings)
        }

        return chunks
    }

    private static func createSectionChunks(
        content: String,
        sectionTitle: String,
        category: ClinicalCategory,
        dateRecorded: Date?,
        patientId: UUID,
        patientFullName: String,
        dateStr: String,
        startIndex: Int
    ) -> [ClinicalChunk] {
        var chunks: [ClinicalChunk] = []
        var chunkIndex = startIndex

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return chunks }

        let prefix = "[\(patientFullName)] [\(dateStr)] [\(sectionTitle)]"

        // Split if over max words
        let words = trimmed.split(separator: " ")
        if words.count <= maxWordsPerChunk {
            chunks.append(ClinicalChunk(
                patientId: patientId,
                content: trimmed,
                contextualPrefix: prefix,
                metadata: ChunkMetadata(
                    chunkIndex: chunkIndex,
                    sourceType: .clinicalRecord,
                    sectionTitle: sectionTitle,
                    dateRecorded: dateRecorded,
                    clinicalCategory: category,
                    patientName: patientFullName,
                    wordCount: words.count
                )
            ))
        } else {
            // Split into sub-chunks
            var start = words.startIndex
            while start < words.endIndex {
                let end = min(start + maxWordsPerChunk, words.endIndex)
                let subContent = words[start..<end].joined(separator: " ")
                chunks.append(ClinicalChunk(
                    patientId: patientId,
                    content: subContent,
                    contextualPrefix: prefix,
                    metadata: ChunkMetadata(
                        chunkIndex: chunkIndex,
                        sourceType: .clinicalRecord,
                        sectionTitle: sectionTitle,
                        dateRecorded: dateRecorded,
                        clinicalCategory: category,
                        patientName: patientFullName,
                        wordCount: end - start
                    )
                ))
                chunkIndex += 1
                start = end
            }
        }

        return chunks
    }

    // MARK: - Medication Chunks

    /// Group medications by patient into 1-2 chunks with full detail.
    static func chunkMedications(_ medications: [LocalMedication], patient: PatientProfile) -> [ClinicalChunk] {
        guard !medications.isEmpty else { return [] }

        let prefix = "[\(patient.fullName)] [Medications]"
        var lines: [String] = []

        for med in medications.sorted(by: { $0.writtenDate > $1.writtenDate }) {
            var line = med.medicationName
            if let dose = med.dose { line += " \(dose)" }
            if let route = med.route { line += " \(route)" }
            if let freq = med.frequency { line += " \(freq)" }
            line += " | Status: \(med.status ?? "Active")"
            if let indication = med.indication { line += " | For: \(indication)" }
            if let safety = med.safetyNotes, !safety.isEmpty {
                line += " | Safety: \(safety.joined(separator: "; "))"
            }
            if let pharmacy = med.pharmacyName { line += " | Rx from \(pharmacy)" }
            lines.append(line)
        }

        let fullContent = lines.joined(separator: "\n")
        let words = fullContent.split(separator: " ")

        if words.count <= maxWordsPerChunk {
            return [ClinicalChunk(
                patientId: patient.id,
                content: fullContent,
                contextualPrefix: prefix,
                metadata: ChunkMetadata(
                    chunkIndex: 0,
                    sourceType: .medication,
                    sectionTitle: "Medications",
                    dateRecorded: medications.first?.writtenDate,
                    clinicalCategory: .medication,
                    patientName: patient.fullName,
                    wordCount: words.count
                )
            )]
        }

        // Split across multiple chunks
        var chunks: [ClinicalChunk] = []
        var currentLines: [String] = []
        var currentWordCount = 0
        var chunkIndex = 0

        for line in lines {
            let lineWords = line.split(separator: " ").count
            if currentWordCount + lineWords > maxWordsPerChunk && !currentLines.isEmpty {
                chunks.append(ClinicalChunk(
                    patientId: patient.id,
                    content: currentLines.joined(separator: "\n"),
                    contextualPrefix: prefix,
                    metadata: ChunkMetadata(
                        chunkIndex: chunkIndex,
                        sourceType: .medication,
                        sectionTitle: "Medications",
                        dateRecorded: medications.first?.writtenDate,
                        clinicalCategory: .medication,
                        patientName: patient.fullName,
                        wordCount: currentWordCount
                    )
                ))
                chunkIndex += 1
                currentLines = []
                currentWordCount = 0
            }
            currentLines.append(line)
            currentWordCount += lineWords
        }

        if !currentLines.isEmpty {
            chunks.append(ClinicalChunk(
                patientId: patient.id,
                content: currentLines.joined(separator: "\n"),
                contextualPrefix: prefix,
                metadata: ChunkMetadata(
                    chunkIndex: chunkIndex,
                    sourceType: .medication,
                    sectionTitle: "Medications",
                    dateRecorded: medications.first?.writtenDate,
                    clinicalCategory: .medication,
                    patientName: patient.fullName,
                    wordCount: currentWordCount
                )
            ))
        }

        return chunks
    }

    // MARK: - Appointment Chunks

    /// Group appointments by patient into 1-2 chunks.
    static func chunkAppointments(_ appointments: [Appointment], patient: PatientProfile) -> [ClinicalChunk] {
        guard !appointments.isEmpty else { return [] }

        let prefix = "[\(patient.fullName)] [Appointments]"
        var lines: [String] = []

        for appt in appointments.sorted(by: { $0.scheduledTime < $1.scheduledTime }) {
            var line = "\(appt.scheduledTime.formatted(date: .abbreviated, time: .shortened)): \(appt.reasonForVisit) [\(appt.status)]"
            if let type = appt.encounterType { line += " | \(type)" }
            if let clinician = appt.clinicianName { line += " | Dr. \(clinician)" }
            if let location = appt.location { line += " | \(location)" }
            if let prep = appt.prepInstructions { line += " | Prep: \(prep)" }
            if let dx = appt.linkedDiagnoses, !dx.isEmpty {
                line += " | Dx: \(dx.joined(separator: ", "))"
            }
            lines.append(line)
        }

        let fullContent = lines.joined(separator: "\n")

        return [ClinicalChunk(
            patientId: patient.id,
            content: fullContent,
            contextualPrefix: prefix,
            metadata: ChunkMetadata(
                chunkIndex: 0,
                sourceType: .appointment,
                sectionTitle: "Appointments",
                dateRecorded: appointments.first?.scheduledTime,
                clinicalCategory: .appointment,
                patientName: patient.fullName,
                wordCount: fullContent.split(separator: " ").count
            )
        )]
    }

    // MARK: - Full Patient Chunking

    /// Chunk all data for a single patient: profile + records + meds + appointments.
    static func chunkAllData(for patient: PatientProfile) -> [ClinicalChunk] {
        var all: [ClinicalChunk] = []

        // Patient profile
        all.append(contentsOf: chunkPatient(patient))

        // Clinical records
        for record in (patient.clinicalRecords ?? []).sorted(by: { $0.dateRecorded > $1.dateRecorded }) {
            all.append(contentsOf: chunkRecord(record, patient: patient))
        }

        // Medications
        all.append(contentsOf: chunkMedications(patient.medications ?? [], patient: patient))

        // Appointments
        all.append(contentsOf: chunkAppointments(patient.appointments ?? [], patient: patient))

        return all
    }
}
