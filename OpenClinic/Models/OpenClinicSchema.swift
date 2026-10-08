import Foundation
import SwiftData
import os

/// The one definition of what the store holds. The app and every test build
/// their container from here, so a model added to this list is everywhere at once.
nonisolated enum OpenClinicSchema {
    static let models: [any PersistentModel.Type] = [
        PatientProfile.self,
        LocalClinicalRecord.self,
        LocalMedication.self,
        Appointment.self,
        ClinicalPhoto.self,
        ChartProblem.self,
        ChartAllergy.self,
        ChartObservation.self,
        ChartEncounter.self,
        ChartProcedure.self,
        ChartImmunization.self,
        ChartDiagnosticReport.self,
        ChartDocument.self,
        FHIRResourceRecord.self,
        AuditEvent.self,
    ]

    static var schema: Schema { Schema(models) }

    /// The on-disk container the app runs on.
    static func makeContainer() throws -> ModelContainer {
        let schema = schema
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
    }

    /// A container that lives in memory, for tests and previews.
    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = schema
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    /// Where the on-disk store lives, for backing it up before a recovery.
    static var storeURL: URL {
        ModelConfiguration(schema: schema).url
    }
}

/// Opens the store at launch and decides what to do when it cannot be opened.
///
/// A store that fails to open is never deleted. It is moved aside with a
/// timestamp so it can be recovered, a fresh store is started, and the app tells
/// the clinician what happened. If even a fresh store cannot be created the app
/// runs on an in-memory store and says so, instead of crashing.
nonisolated enum StoreBootstrap {
    struct Result: Sendable {
        let container: ModelContainer
        /// A message for the clinician when the saved store was not used. Nil on a normal launch.
        let issue: String?
    }

    static func open() -> Result {
        do {
            return Result(container: try OpenClinicSchema.makeContainer(), issue: nil)
        } catch {
            AppLogger.app.error("Store could not be opened: \(error.localizedDescription, privacy: .public)")
        }

        let backupName = moveStoreAside()
        do {
            let container = try OpenClinicSchema.makeContainer()
            let where_ = backupName.map { " The previous store was kept as \($0)." } ?? ""
            return Result(
                container: container,
                issue: "The saved chart store could not be opened, so OpenClinic started a new one.\(where_)"
            )
        } catch {
            AppLogger.app.fault("A new store could not be created: \(error.localizedDescription, privacy: .public)")
        }

        do {
            return Result(
                container: try OpenClinicSchema.makeInMemoryContainer(),
                issue: "OpenClinic could not open or create its chart store. It is running on temporary storage, and nothing entered in this session will be saved."
            )
        } catch {
            // Without any container no view can load. This is the one unrecoverable launch failure.
            fatalError("OpenClinic could not create a model container: \(error)")
        }
    }

    /// Renames the store files with a timestamp and returns the new base name, or nil if nothing was moved.
    private static func moveStoreAside() -> String? {
        let storeURL = OpenClinicSchema.storeURL
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: storeURL.path) else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupName = storeURL.deletingPathExtension().lastPathComponent + "-unreadable-" + formatter.string(from: .now)
        let backupBase = storeURL.deletingLastPathComponent().appendingPathComponent(backupName)

        var moved = false
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = URL(fileURLWithPath: backupBase.path + "." + storeURL.pathExtension + suffix)
            do {
                try fileManager.moveItem(at: source, to: destination)
                moved = true
            } catch {
                AppLogger.app.error("Could not move \(source.lastPathComponent, privacy: .public) aside: \(error.localizedDescription, privacy: .public)")
            }
        }
        return moved ? backupName : nil
    }
}

/// The app's one open store. The scene and the App Intents share this container,
/// so no second container is ever opened on the same file with a different schema.
nonisolated enum AppStore {
    static let shared: StoreBootstrap.Result = StoreBootstrap.open()
}
