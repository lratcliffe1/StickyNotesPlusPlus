import Foundation
import XCTest

final class MorningModeProviderTests: XCTestCase {
    func testLoadsCutoffModeByDefault() {
        let suite = suiteName()
        let defaults = makeDefaults(suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = MorningModeProvider.load(from: defaults)
        XCTAssertEqual(settings.selection, .cutoff)
    }

    func testClampsWindowDuration() {
        let suite = suiteName()
        let defaults = makeDefaults(suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(AppSettings.MorningMode.sinceWakeUp.rawValue, forKey: AppSettings.morningModeKey)
        defaults.set(1_000, forKey: AppSettings.morningWindowDurationMinutesKey)

        let settings = MorningModeProvider.load(from: defaults)
        XCTAssertEqual(settings.selection, .sinceWakeUp)
        XCTAssertEqual(settings.windowDurationMinutes, 240)
    }

    private func suiteName() -> String {
        "MorningModeProviderTests.\(UUID().uuidString)"
    }

    private func makeDefaults(suite: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
