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

    /// `vault-reconcile.lock` in the App Group container (resolved from `ALTAppGroups`). Without a
    /// container (no entitlement), a per-process temporary file: the lock then only guards this
    /// process.
    static func shared() -> VaultFileLock {
        let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedPersistence.appGroupIdentifier
        ) ?? FileManager.default.temporaryDirectory
        return VaultFileLock(url: directory.appendingPathComponent("vault-reconcile.lock"))
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

    /// The lock if it is free right now, else nil.
    func tryLock() -> Held? {
        let descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else {
            AppLogger.vault.error("Lock file unavailable: \(errno, privacy: .public)")
            return nil
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        return Held(descriptor: descriptor)
    }

    /// Keeps trying for up to `maxWait` seconds without blocking the thread (it sleeps between
    /// tries). 0: one try.
    func lock(waitingUpTo maxWait: TimeInterval) async -> Held? {
        let deadline = Date().addingTimeInterval(maxWait)
        while true {
            if let held = tryLock() { return held }
            guard Date() < deadline else { return nil }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
