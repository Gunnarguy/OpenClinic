//
//  OpenClinicApp.swift
//  OpenClinic
//
//  Created by Gunnar Hostetler on 3/20/26.
//

import SwiftUI
import SwiftData
import os

@main
struct OpenClinicApp: App {
    @StateObject private var smartConnectionController = SMARTConnectionController()
    private let container: ModelContainer
    /// Set when the saved store could not be used at launch.
    @State private var storeIssue: String?

    init() {
        let store = AppStore.shared
        container = store.container
        _storeIssue = State(initialValue: store.issue)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(smartConnectionController)
                .onOpenURL { url in
                    Task {
                        await smartConnectionController.handleOpenURL(url)
                    }
                }
                .alert("Chart store", isPresented: Binding(get: { storeIssue != nil }, set: { if !$0 { storeIssue = nil } })) {
                    Button("OK", role: .cancel) { storeIssue = nil }
                } message: {
                    Text(storeIssue ?? "")
                }
                .task {
                    // The demo panel is seeded before indexing, so the first
                    // launch indexes a full chart set and not an empty store.
                    do {
                        try DemoDataSeeder.prepare(context: container.mainContext)
                    } catch {
                        AppLogger.data.error("Demo panel could not be prepared: \(error.localizedDescription)")
                    }
                    AppLogger.app.info("🔄 Triggering RAG reindex on launch")
                    await ClinicalRAGService.shared.indexAllData(modelContext: container.mainContext)
                }
        }
        .modelContainer(container)
    }
}
