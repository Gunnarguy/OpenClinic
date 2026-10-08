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
                    // A chart imported by an earlier version can hold a government number in its stored
                    // Patient resource, or a placeholder date of birth. Every import since stores neither,
                    // so the repair runs until it has finished once on the saved store. A store that
                    // could not be opened is not the saved store, and does not count.
                    let repairedKey = "OpenClinic.earlierChartsRepaired.v1"
                    if storeIssue == nil, !UserDefaults.standard.bool(forKey: repairedKey),
                       let repaired = ChartImportApplier.repairChartsFromEarlierVersions(in: container.mainContext) {
                        UserDefaults.standard.set(true, forKey: repairedKey)
                        if repaired > 0 {
                            AppLogger.data.info("Repaired \(repaired, privacy: .public) values in charts imported by an earlier version")
                        }
                    }
                    // Only what changed since the index was saved is embedded again.
                    AppLogger.app.info("🔄 Syncing the retrieval index on launch")
                    let launchSync = await ClinicalRAGService.shared.syncIndex(modelContext: container.mainContext)
                    #if DEBUG
                    if DeviceSelfCheck.isRequested {
                        await DeviceSelfCheck.run(container: container, storeIssue: storeIssue, launchSync: launchSync)
                    }
                    #else
                    _ = launchSync
                    #endif
                }
        }
        .modelContainer(container)
    }
}
