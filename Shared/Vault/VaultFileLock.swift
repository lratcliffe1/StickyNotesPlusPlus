import Darwin
import Foundation
import os

/// A cross-process lock on a file in the App Group container, so the app and the widget never
/// reconcile at the same time (the manifest is read, the store written, then the manifest written).
/// `flock` with `LOCK_EX | LOCK_NB`: it never blocks; callers decide how long to keep trying.
/// The lock goes with the file descriptor, so it is released if the process dies.
final class VaultFileLock {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    /// `vault-reconcile.lock` in the App Group container (resolved from `ALTAppGroups`), or nil
    /// when there is no container (no App Group entitlement): then the widget doesn't import at
    /// all and the app is the only reconciler.
    static func shared() -> VaultFileLock? {
        guard let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedPersistence.appGroupIdentifier
        ) else {
            AppLogger.vault.error("No App Group container: no cross-process lock")
            return nil
        }
        return VaultFileLock(url: directory.appendingPathComponent("vault-reconcile.lock"))
    }

    enum Attempt {
        case held(Held)
        /// Another holder has it.
        case busy
        /// The lock file couldn't be opened (`errno`).
        case unavailable(Int32)

        var held: Held? {
            if case let .held(held) = self { return held }
            return nil
        }
    }

    /// A held lock. Released by `release()` or when it goes away.
    final class Held {
        private var descriptor: Int32

        fileprivate init(descriptor: Int32) {
            self.descriptor = descriptor
        }

        func release() {
            guard descriptor >= 0 else { return }
            flock(descriptor, LOCK_UN)
            close(descriptor)
            descriptor = -1
        }

        deinit {
            release()
        }
    }

    /// The lock if it is free right now.
    func tryLock() -> Attempt {
        let descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else {
            let code = errno
            AppLogger.vault.error("Lock file unavailable: \(code, privacy: .public)")
            return .unavailable(code)
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return .busy
        }
        return .held(Held(descriptor: descriptor))
    }

    /// Keeps trying for up to `maxWait` seconds without blocking the thread (it sleeps between
    /// tries). 0: one try. An unopenable file gives up at once.
    func lock(waitingUpTo maxWait: TimeInterval) async -> Attempt {
        let deadline = Date().addingTimeInterval(maxWait)
        while true {
            let attempt = tryLock()
            guard case .busy = attempt, Date() < deadline else { return attempt }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
