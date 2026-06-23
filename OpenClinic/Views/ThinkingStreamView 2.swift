import SwiftUI

struct ThinkingStreamView: View {
    let events: [ThinkingStep]

    @State private var isExpanded = true
    @State private var isFullHeight = false
    @State private var hasAutoExpanded = false

    private var latestEvent: ThinkingStep? {
        events.last
    }

    private var pipelineElapsed: TimeInterval? {
        guard let first = events.first, let last = events.last else { return nil }
        return last.timestamp.timeIntervalSince(first.timestamp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isExpanded.toggle() } }) {
                headerView
            }
            .buttonStyle(.plain)

            if isExpanded {
                consoleLogView
                    .transition(.asymmetric(
                        insertion: .push(from: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isExpanded)
        .animation(.easeInOut(duration: 0.15), value: events.count)
        .onChange(of: events.count) { _, newCount in
            if newCount >= 1 && !hasAutoExpanded {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isExpanded = true
                    hasAutoExpanded = true
                }
            }
        }
        .onChange(of: events.isEmpty) { _, isEmpty in
            if isEmpty {
                hasAutoExpanded = false
            }
        }
    }

    private var headerView: some View {
        HStack(spacing: 6) {
            ThinkingPulse()

            if let latest = latestEvent {
                Text(latest.title)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(colorFor(latest.phase))
                    .lineLimit(1)

                if !latest.detail.isEmpty {
                    Text("·")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.gray.opacity(0.5))
                    Text(latest.detail)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.gray.opacity(0.8))
                        .lineLimit(1)
                }
            } else {
                Text("Initializing...")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.gray)
            }

            Spacer(minLength: 4)

            if events.count > 0 {
                HStack(spacing: 3) {
                    Text("\(events.count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.blue)

                    if let elapsed = pipelineElapsed, elapsed > 0.1 {
                        Text("·")
                            .font(.system(size: 6))
                            .foregroundStyle(Color.gray.opacity(0.4))
                        Text(String(format: "%.0fms", elapsed * 1000))
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.gray.opacity(0.7))
                    }
                }
            }

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.gray.opacity(0.5))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.clinicSecondarySystemBackground.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var consoleLogView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(events) { event in
                            ConsoleLogRow(event: event, isLatest: event.id == latestEvent?.id)
                                .id(event.id)
                        }
                    }
                }
                .frame(maxHeight: isFullHeight ? 350 : 120)
                .onChange(of: events.count) { _, _ in
                    if let latest = latestEvent {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(latest.id, anchor: .bottom)
                        }
                    }
                }
            }

            if events.count > 8 {
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isFullHeight.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isFullHeight ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 7, weight: .medium))
                        Text(isFullHeight ? "Compact" : "Full History (\(events.count))")
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(Color.blue.opacity(0.7))
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.03))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.blue.opacity(0.2), lineWidth: 0.5)
        )
        .padding(.top, 2)
    }

    private func colorFor(_ phase: ThinkingPhase) -> Color {
        switch phase {
        case .queryAnalysis: return .purple
        case .embedding: return .blue
        case .vectorSearch, .keywordSearch: return .green
        case .rrfFusion, .reranking, .mmrDiversity: return .orange
        case .tokenBudget, .lostInMiddle, .contextAssembly: return .teal
        case .verification, .deepThinkPass, .followUpExtraction: return .pink
        case .generation, .complete: return .mint
        }
    }
}

private struct ConsoleLogRow: View {
    let event: ThinkingStep
    let isLatest: Bool

    private var tint: Color {
        switch event.phase {
        case .queryAnalysis: return .purple
        case .embedding: return .blue
        case .vectorSearch, .keywordSearch: return .green
        case .rrfFusion, .reranking, .mmrDiversity: return .orange
        case .tokenBudget, .lostInMiddle, .contextAssembly: return .teal
        case .verification, .deepThinkPass, .followUpExtraction: return .pink
        case .generation, .complete: return .mint
        }
    }

    private var timestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "mm:ss"
        return formatter.string(from: event.timestamp)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Text(timestamp)
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.gray.opacity(0.5))
                .frame(width: 28, alignment: .leading)

            Text(shortPhaseLabel)
                .font(.system(size: 6, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
                .frame(width: 36, alignment: .leading)

            Text(event.title)
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(isLatest ? Color.white : Color.white.opacity(0.8))
                .lineLimit(1)

            if !event.detail.isEmpty {
                Text("→")
                    .font(.system(size: 6))
                    .foregroundStyle(Color.gray.opacity(0.4))
                Text(event.detail)
                    .font(.system(size: 7, weight: .regular, design: .monospaced))
                    .foregroundStyle(tint.opacity(0.85))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isLatest {
                Circle()
                    .fill(tint)
                    .frame(width: 3, height: 3)
            }
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 2)
        .background(isLatest ? tint.opacity(0.08) : Color.clear)
    }

    private var shortPhaseLabel: String {
        switch event.phase {
        case .queryAnalysis: return "QUERY"
        case .embedding: return "EMBED"
        case .vectorSearch: return "VECTOR"
        case .keywordSearch: return "FTS5"
        case .rrfFusion: return "RRF"
        case .reranking: return "RERANK"
        case .mmrDiversity: return "MMR"
        case .tokenBudget: return "BUDGET"
        case .lostInMiddle: return "REORDR"
        case .contextAssembly: return "ASSMBL"
        case .verification: return "VERIFY"
        case .deepThinkPass: return "THINK"
        case .followUpExtraction: return "XTRCT"
        case .generation: return "GENER8"
        case .complete: return "DONE"
        }
    }
}

private struct ThinkingPulse: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.blue)
            .frame(width: 5, height: 5)
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
