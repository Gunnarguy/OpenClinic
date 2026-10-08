import SwiftUI
import SwiftData
import os

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isDemoDataReady = false

    var body: some View {
        if isDemoDataReady {
            EHRMainShellView()
        } else {
            // The shell waits for the demo panel, so no view reads a half-seeded store
            // or holds a patient that a reseed is about to replace. Preparing is
            // synchronous and quick, so this placeholder is on screen for one frame.
            Color.clear
                .task {
                    do {
                        try DemoDataSeeder.prepare(context: modelContext)
                    } catch {
                        AppLogger.data.error("Demo data could not be prepared: \(error.localizedDescription)")
                    }
                    isDemoDataReady = true
                }
        }
    }
}
