import Foundation
import SwiftData
import os

/// Shared SwiftData container factory + legacy store migration into the App Group location.
enum SharedPersistence {
    static let appGroupIdentifier = resolveAppGroupIdentifier()
    private static let defaultAppGroupIdentifier = "group.com.liamratcliffe.Sticky-Notes-Sticky-Life"
    private static let sharedStoreName = "StickyNotesSharedStore"

    /// SideStore/AltStore re-sign with a free Apple ID by renaming the App Group, and list the
    /// real identifiers under `ALTAppGroups` in Info.plist. The widget reads its containing app's
    /// Info.plist too, in case only the app's was rewritten. Xcode builds fall back to the default.
    private static func resolveAppGroupIdentifier() -> String {
        let containingAppURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        let bundles = [Bundle.main, Bundle(url: containingAppURL)].compactMap { $0 }
        for bundle in bundles {
            guard let groups = bundle.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] else { continue }
            if let match = groups.first(where: { $0.hasPrefix(defaultAppGroupIdentifier) }) ?? groups.first {
                return match
            }
        }
        return defaultAppGroupIdentifier
    }

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static func appSchema() -> Schema {
        Schema([
            MorningRoutineTemplateItem.self,
            MorningRoutineEntry.self,
            DailyTask.self,
            DayRecord.self,
        ])
    }

    static func makeContainer(schema: Schema = appSchema()) throws -> ModelContainer {
        migrateLegacyStoreIfNeeded(schema: schema)
        let config = ModelConfiguration(
            sharedStoreName,
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .identifier(appGroupIdentifier),
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    private static func migrateLegacyStoreIfNeeded(schema: Schema) {
        let legacyConfig = ModelConfiguration(
            nil,
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )

        let sharedConfig = ModelConfiguration(
            sharedStoreName,
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .identifier(appGroupIdentifier),
            cloudKitDatabase: .none
        )

        let fileManager = FileManager.default
        let legacyURL = legacyConfig.url
        let sharedURL = sharedConfig.url

        guard fileManager.fileExists(atPath: legacyURL.path) else { return }
        guard !fileManager.fileExists(atPath: sharedURL.path) else { return }

        do {
            try fileManager.createDirectory(
                at: sharedURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try copyStoreFamily(from: legacyURL, to: sharedURL, fileManager: fileManager)
        } catch {
            AppLogger.persistence.error("SharedPersistence migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func copyStoreFamily(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager
    ) throws {
        let families: [(URL, URL)] = [
            (sourceURL, destinationURL),
            (sqliteSidecarURL(for: sourceURL, suffix: "-shm"), sqliteSidecarURL(for: destinationURL, suffix: "-shm")),
            (sqliteSidecarURL(for: sourceURL, suffix: "-wal"), sqliteSidecarURL(for: destinationURL, suffix: "-wal")),
        ]

        for (source, destination) in families where fileManager.fileExists(atPath: source.path) {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    private static func sqliteSidecarURL(for baseURL: URL, suffix: String) -> URL {
        URL(fileURLWithPath: baseURL.path + suffix)
    }
}
