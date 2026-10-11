import Foundation

/// `stickynotes://bump?id=<occurrence id>`: the widget's bump button when Retype to bump is on.
/// It opens the app on that row's bump sheet instead of bumping in one tap.
enum BumpDeepLink {
    static func url(for occurrenceID: UUID) -> URL {
        var components = URLComponents()
        components.scheme = "stickynotes"
        components.host = "bump"
        components.queryItems = [URLQueryItem(name: "id", value: occurrenceID.uuidString)]
        return components.url ?? URL(string: "stickynotes://bump")!
    }

    /// The occurrence id in a bump link, or nil for any other URL.
    static func occurrenceID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == "stickynotes", url.host?.lowercased() == "bump" else { return nil }
        let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "id" }?
            .value
        return value.flatMap(UUID.init(uuidString:))
    }
}
