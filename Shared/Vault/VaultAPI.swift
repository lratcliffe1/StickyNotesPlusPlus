import Foundation
import os

/// Where the vault files live and how requests to them are built (`docs/VAULT-API.md`).
///
/// The app talks to the GitHub contents API of the vault repo with a fine-grained token that only
/// opens that repo (Contents: read and write). Path segments are percent-encoded one by one, so
/// `7 Projects/StickyNotes/tasks.json` becomes `7%20Projects/StickyNotes/tasks.json`.
enum VaultAPI {
    static let owner = "lratcliffe1"
    static let repo = "Obsidian"
    static let apiBase = "https://api.github.com"
    static let apiVersion = "2022-11-28"

    static let areaPath = "7 Projects/StickyNotes"
    static let tasksPath = "\(areaPath)/tasks.json"

    /// `habits/YYYY-MM.json` for a month key (`YYYY-MM`).
    static func habitsPath(month: String) -> String {
        "\(areaPath)/habits/\(month).json"
    }

    /// Characters left as they are in a path segment (RFC 3986 unreserved).
    private static let segmentAllowed: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return set
    }()

    /// Percent-encodes each segment of a repo path, keeping the slashes between them.
    static func encodedPath(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: segmentAllowed) ?? String($0) }
            .joined(separator: "/")
    }

    static func contentsURL(for path: String) -> URL? {
        URL(string: "\(apiBase)/repos/\(owner)/\(repo)/contents/\(encodedPath(path))")
    }

    static var repoURL: URL? {
        URL(string: "\(apiBase)/repos/\(owner)/\(repo)")
    }

    /// The media types the contents API takes: the file's raw bytes, or the JSON wrapper (sha,
    /// base64 content) that a write needs.
    enum Accept: String {
        case raw = "application/vnd.github.raw+json"
        case json = "application/vnd.github+json"
    }

    /// A request with the token and API version set. The token goes in the header only: never in
    /// the URL, never in a log.
    static func request(url: URL, method: String = "GET", token: String, accept: Accept, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(accept.rawValue, forHTTPHeaderField: "Accept")
        request.setValue("StickyNotesPlusPlus", forHTTPHeaderField: "User-Agent")
        return request
    }
}

extension AppLogger {
    /// The vault link. Logs status codes and outcomes only: never the token, never file contents.
    static let vault = Logger(subsystem: Bundle.main.bundleIdentifier ?? "StickyNotesStickyLife", category: "vault")
}
