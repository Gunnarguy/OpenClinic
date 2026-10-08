//
//  AuditLogView.swift
//  OpenClinic
//
//  The access log: imports, source-resource views, signed notes and demo
//  resets, newest first. Entries name the record that was touched and never
//  hold clinical content.
//

import SwiftUI
import SwiftData

struct AuditLogView: View {
    @Query(sort: \AuditEvent.timestamp, order: .reverse) private var events: [AuditEvent]

    var body: some View {
        List {
            if events.isEmpty {
                ContentUnavailableView(
                    "No entries yet",
                    systemImage: "list.bullet.clipboard",
                    description: Text("Record imports, source views and demo resets are logged here.")
                )
            }

            ForEach(events) { event in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(label(for: event))
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(event.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute().second())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if let detail = event.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Text(event.actor)
                        if let entityType = event.entityType {
                            Text(entityType)
                        }
                        if let entityID = event.entityID {
                            Text(entityID)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("Access Log")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func label(for event: AuditEvent) -> String {
        AuditAction(rawValue: event.action)?.label ?? event.action
    }
}
