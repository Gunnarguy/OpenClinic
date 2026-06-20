import SwiftUI
import SwiftData
import Combine
import os

private struct AssistantMessage: Identifiable {
    let id: UUID
    let isUser: Bool
    let text: String
    let sourceDescriptor: ClinicalSourceDescriptor?
    let thinkingSteps: [ThinkingStep]?

    init(id: UUID = UUID(), isUser: Bool, text: String, sourceDescriptor: ClinicalSourceDescriptor? = nil, thinkingSteps: [ThinkingStep]? = nil) {
        self.id = id
        self.isUser = isUser
        self.text = text
        self.sourceDescriptor = sourceDescriptor
        self.thinkingSteps = thinkingSteps
    }
}

struct ClinicalAssistantView: View {
    let patient: PatientProfile
    @Environment(\.modelContext) private var modelContext
    @StateObject private var intelligenceService = ClinicalIntelligenceService()
    @ObservedObject private var ragService = ClinicalRAGService.shared

    @State private var queryText = ""
    @State private var chatHistory: [AssistantMessage] = []
    @State private var isProcessing = false
    private let contentMaxWidth: CGFloat = 920

    private var quickPrompts: [String] {
        [
            "Does \(patient.firstName) have a history of Basal Cell Carcinoma?",
            "What medications are on file for \(patient.firstName)?",
            "When is the next follow-up and what is it for?",
            "What allergies or risk flags should I know before treatment?"
        ]
    }

    var body: some View {
        ZStack {
            Color.clinicSystemGroupedBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .foregroundColor(.secondary)
                Text(intelligenceService.engineStatusLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .clinicalFinePrint()
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .frame(maxWidth: contentMaxWidth)

            // Quick prompts
            GeometryReader { geometry in
                let cardMaxWidth = min(max(geometry.size.width * 0.6, 160), 210)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickPrompts, id: \.self) { prompt in
                            Button {
                                askAssistant(with: prompt)
                            } label: {
                                Text(prompt)
                                    .font(.caption)
                                    .clinicalFinePrint()
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: cardMaxWidth, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 9)
                                    .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .frame(maxWidth: contentMaxWidth, alignment: .leading)
                }
            }
            .frame(height: 96)

            Divider()

            // Chat messages
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(chatHistory) { message in
                        HStack {
                            if message.isUser {
                                Spacer()
                                Text(message.text)
                                    .font(.subheadline)
                                    .lineSpacing(2)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            } else {
                                HStack(alignment: .top, spacing: 10) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.blue)
                                        .frame(width: 3)
                                        .padding(.vertical, 6)

                                    VStack(alignment: .leading, spacing: 8) {
                                        if let sourceDescriptor = message.sourceDescriptor {
                                            HStack(spacing: 6) {
                                                ClinicalSourceBadge(descriptor: sourceDescriptor)
                                                if let systemName = sourceDescriptor.systemName, !systemName.isEmpty {
                                                    Text(systemName)
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                        .clinicalFinePrint()
                                                }
                                            }
                                        }
                                        
                                        if let steps = message.thinkingSteps, !steps.isEmpty {
                                            ThinkingStreamView(events: steps)
                                                .padding(.bottom, 4)
                                        }

                                        ChatFormattedText(text: message.text)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(Color.clinicSecondarySystemBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(.quaternary, lineWidth: 0.5)
                                    )
                                }
                                Spacer(minLength: 40)
                            }
                        }
                        .padding(.horizontal)
                    }
                    if isProcessing {
                        HStack {
                            ThinkingStreamView(events: ragService.thinkingSteps)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal)
                    }
                }
                .frame(maxWidth: contentMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }

            // Input bar
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 12) {
                    TextField("Ask about \(patient.firstName)'s history...", text: $queryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.clinicSecondarySystemBackground.opacity(0.8))
                        .clipShape(Capsule())
                        .onSubmit(askAssistant)

                    Button(action: askAssistant) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(queryText.isEmpty ? .secondary.opacity(0.5) : .blue)
                    }
                    .disabled(queryText.isEmpty || isProcessing)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .frame(maxWidth: contentMaxWidth)
                .background(.ultraThinMaterial)
            }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("AI Assistant")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            if chatHistory.isEmpty {
                chatHistory.append(AssistantMessage(isUser: false, text: "I'm your on-device clinical assistant for \(patient.fullName). I can summarize visits, medications, allergies, risk flags, and upcoming follow-up directly from the local chart.", sourceDescriptor: ClinicalSourceDescriptor(kind: .localAI, systemName: patient.sourceDescriptor.systemName ?? "Local Chart Cache", authoritative: false, lastSyncedAt: patient.sourceDescriptor.lastSyncedAt)))
            }
        }
    }

    private func askAssistant() {
        let q = queryText
        queryText = ""
        askAssistant(with: q)
    }

    private func askAssistant(with query: String) {
        guard !query.isEmpty else { return }
        AppLogger.assistant.info("💬 Patient query: \(query.prefix(80))")
        chatHistory.append(AssistantMessage(isUser: true, text: query))
        isProcessing = true

        Task {
            do {
                let response = try await intelligenceService.executeToolQuery(query: query, modelContext: modelContext, patient: patient)
                AppLogger.assistant.info("✅ Assistant response: \(response.count) chars")
                chatHistory.append(AssistantMessage(isUser: false, text: response, sourceDescriptor: ClinicalSourceDescriptor(kind: .localAI, systemName: patient.sourceDescriptor.systemName ?? "Local Chart Cache", authoritative: false, lastSyncedAt: patient.sourceDescriptor.lastSyncedAt), thinkingSteps: intelligenceService.ragMetadata?.thinkingSteps))
                isProcessing = false
            } catch {
                AppLogger.assistant.error("❌ Assistant query failed: \(error.localizedDescription)")
                chatHistory.append(AssistantMessage(isUser: false, text: "Error: \(error.localizedDescription)", sourceDescriptor: ClinicalSourceDescriptor(kind: .localAI, systemName: patient.sourceDescriptor.systemName ?? "Local Chart Cache", authoritative: false, lastSyncedAt: patient.sourceDescriptor.lastSyncedAt)))
                isProcessing = false
            }
        }
    }
}

private struct ChatFormattedText: View {
    let text: String

    private var lines: [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespaces)

                if line.isEmpty {
                    Color.clear.frame(height: index == 0 ? 0 : 2)
                } else if line.hasPrefix("- ") {
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)
                        Text(String(line.dropFirst(2)))
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if line.hasSuffix(":") && line.count < 40 {
                    Text(line)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.top, index == 0 ? 0 : 2)
                } else {
                    Text(line)
                        .font(.subheadline)
                        .lineSpacing(2)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}
