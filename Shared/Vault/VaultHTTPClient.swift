import Foundation

/// The one thing the vault link needs from the network: send a request, get the bytes and the
/// HTTP response. The app uses `URLSessionVaultHTTPClient`; tests and the screenshot harness use
/// a fake, so they never touch the network.
protocol VaultHTTPClient {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The real client. An ephemeral session with no URL cache, so a 304 reaches the caller as a 304
/// (the ETag is handled here, by hand) and nothing the API returns is written to disk.
struct URLSessionVaultHTTPClient: VaultHTTPClient {
    let session: URLSession

    /// `timeout` bounds each request and the whole transfer (the widget passes ~5 s).
    init(timeout: TimeInterval = 20) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

#if DEBUG
/// Tests and the screenshot harness: answers every request from `handler`, records what was sent,
/// never opens a connection.
final class FakeVaultHTTPClient: VaultHTTPClient {
    struct Reply {
        var status: Int = 200
        var headers: [String: String] = [:]
        var body = Data()
        /// Thrown instead of answering (e.g. `URLError(.notConnectedToInternet)`).
        var error: URLError?

        init(status: Int = 200, headers: [String: String] = [:], body: Data = Data(), error: URLError? = nil) {
            self.status = status
            self.headers = headers
            self.body = body
            self.error = error
        }
    }

    var handler: (URLRequest) -> Reply
    private(set) var requests: [URLRequest] = []

    init(handler: @escaping (URLRequest) -> Reply) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let reply = handler(request)
        if let error = reply.error {
            throw error
        }
        guard
            let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)
        else { throw URLError(.badURL) }
        return (reply.body, response)
    }
}
#endif
