import Foundation
import os

/// What can go wrong talking to GitHub, already sorted into what the status line says.
enum VaultError: Error, Equatable {
    /// 401, or a 403 that isn't rate limiting: the token is wrong, revoked, or lacks the repo.
    case tokenNotAccepted
    /// 401 after the token's expiry date (GitHub sends it with every answer), or GitHub says so.
    case tokenExpired
    /// 404 for a file in a repo the token can see.
    case notFound
    /// No network, or GitHub couldn't be reached in time.
    case offline
    /// 409 / 422 on a write: the file changed since its sha was read.
    case conflict
    /// Rate limited, or GitHub had a problem (5xx, anything unexpected).
    case github(status: Int)
    /// The answer wasn't what the API documents.
    case badResponse
}

/// The GitHub contents API calls the vault link makes. Everything goes through a `VaultHTTPClient`,
/// so tests drive it with a fake.
struct VaultGitHubClient {
    let http: VaultHTTPClient
    var timeout: TimeInterval = 20
    /// Where the token's expiry date is kept (GitHub sends it on every authenticated answer);
    /// a 401 after it reads as "Token expired". Not secret.
    var expiryStore: VaultTokenExpiryStore?
    var now: () -> Date = { Date() }

    enum TasksResult: Equatable {
        /// 304: unchanged since `etag`.
        case notModified
        case fetched(data: Data, etag: String?)
    }

    struct RemoteFile: Equatable {
        let content: Data
        let sha: String
    }

    // MARK: - tasks.json (raw, with ETag)

    func fetchTasks(token: String, etag: String?) async -> Result<TasksResult, VaultError> {
        guard let url = VaultAPI.contentsURL(for: VaultAPI.tasksPath) else { return .failure(.badResponse) }
        var request = VaultAPI.request(url: url, token: token, accept: .raw, timeout: timeout)
        if let etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        switch await send(request) {
        case let .failure(error):
            return .failure(error)
        case let .success((data, response)):
            switch response.statusCode {
            case 304:
                return .success(.notModified)
            case 200:
                return .success(.fetched(data: data, etag: response.value(forHTTPHeaderField: "ETag")))
            case 404:
                // A token that can't see the repo gets 404s too: tell that apart from "no file yet".
                return .failure(await repoVisible(token: token) ? .notFound : .tokenNotAccepted)
            default:
                return .failure(error(for: response, data: data))
            }
        }
    }

    // MARK: - habits files (JSON form: sha + base64)

    /// The file and its sha, or nil when it doesn't exist yet.
    func getFile(path: String, token: String) async -> Result<RemoteFile?, VaultError> {
        guard let url = VaultAPI.contentsURL(for: path) else { return .failure(.badResponse) }
        let request = VaultAPI.request(url: url, token: token, accept: .json, timeout: timeout)
        switch await send(request) {
        case let .failure(error):
            return .failure(error)
        case let .success((data, response)):
            switch response.statusCode {
            case 200:
                guard
                    let body = try? JSONDecoder().decode(ContentsBody.self, from: data),
                    let content = Data(base64Encoded: body.content ?? "", options: .ignoreUnknownCharacters)
                else { return .failure(.badResponse) }
                return .success(RemoteFile(content: content, sha: body.sha))
            case 404:
                return await repoVisible(token: token) ? .success(nil) : .failure(.tokenNotAccepted)
            default:
                return .failure(error(for: response, data: data))
            }
        }
    }

    /// Creates or replaces a file: one commit on the default branch. `sha` is the replaced file's
    /// (nil to create it). 409 / 422 come back as `.conflict`.
    func putFile(path: String, content: Data, sha: String?, message: String, token: String) async -> Result<Void, VaultError> {
        guard let url = VaultAPI.contentsURL(for: path) else { return .failure(.badResponse) }
        var request = VaultAPI.request(url: url, method: "PUT", token: token, accept: .json, timeout: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = PutBody(message: message, content: content.base64EncodedString(), sha: sha)
        guard let encoded = try? JSONEncoder().encode(body) else { return .failure(.badResponse) }
        request.httpBody = encoded
        switch await send(request) {
        case let .failure(error):
            return .failure(error)
        case let .success((data, response)):
            switch response.statusCode {
            case 200, 201:
                return .success(())
            case 409, 422:
                return .failure(.conflict)
            default:
                return .failure(error(for: response, data: data))
            }
        }
    }

    // MARK: - Helpers

    private struct ContentsBody: Decodable {
        let sha: String
        let content: String?
    }

    private struct PutBody: Encodable {
        let message: String
        let content: String
        let sha: String?
    }

    private struct MessageBody: Decodable {
        let message: String?
    }

    private func send(_ request: URLRequest) async -> Result<(Data, HTTPURLResponse), VaultError> {
        do {
            let (data, response) = try await http.send(request)
            rememberExpiry(from: response)
            AppLogger.vault.info("GitHub \(request.httpMethod ?? "GET", privacy: .public) → \(response.statusCode, privacy: .public)")
            return .success((data, response))
        } catch {
            // URLError (no network, timeout, DNS…) or anything else that kept the answer away.
            return .failure(.offline)
        }
    }

    /// Whether the token can see the repo at all (a 404 on a file is then a missing file).
    private func repoVisible(token: String) async -> Bool {
        guard let url = VaultAPI.repoURL else { return false }
        let request = VaultAPI.request(url: url, token: token, accept: .json, timeout: timeout)
        if case let .success((_, response)) = await send(request) {
            return response.statusCode == 200
        }
        // Couldn't check: assume the repo is there, so a flaky check never reads as a bad token.
        return true
    }

    func error(for response: HTTPURLResponse, data: Data) -> VaultError {
        let message = (try? JSONDecoder().decode(MessageBody.self, from: data))?.message?.lowercased() ?? ""
        switch response.statusCode {
        case 401:
            if message.contains("expired") { return .tokenExpired }
            if let expiry = expiryStore?.expiry, expiry <= now() { return .tokenExpired }
            return .tokenNotAccepted
        case 403, 429:
            if response.statusCode == 429
                || response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0"
                || message.contains("rate limit") {
                return .github(status: response.statusCode)
            }
            return .tokenNotAccepted
        case 404:
            return .notFound
        case 409, 422:
            return .conflict
        default:
            return .github(status: response.statusCode)
        }
    }

    /// GitHub sends `GitHub-Authentication-Token-Expiration: 2027-10-12 08:00:00 +0200` with every
    /// answer to a token that expires.
    private func rememberExpiry(from response: HTTPURLResponse) {
        guard
            let expiryStore,
            let value = response.value(forHTTPHeaderField: "GitHub-Authentication-Token-Expiration"),
            let date = Self.parseExpiry(value)
        else { return }
        expiryStore.expiry = date
    }

    static func parseExpiry(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        for format in ["yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd HH:mm:ss zzz"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value.trimmingCharacters(in: .whitespaces)) {
                return date
            }
        }
        return nil
    }
}

/// Keeps the token's expiry date (from GitHub's header) in the App Group defaults.
final class VaultTokenExpiryStore {
    static let key = "vault_token_expiry"
    let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var expiry: Date? {
        get { defaults.object(forKey: Self.key) as? Date }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Self.key)
            } else {
                defaults.removeObject(forKey: Self.key)
            }
        }
    }
}
