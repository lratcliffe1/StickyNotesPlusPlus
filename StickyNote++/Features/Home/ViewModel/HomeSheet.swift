import Foundation

/// The sheets Home presents (one at a time), driven by `HomeViewModel.activeSheet`.
enum HomeSheet: Identifiable, Equatable {
    /// "Bump to tomorrow" for an occurrence.
    case bump(UUID)
    /// Edit… on a one-off: this row's title, deadline and bump limit.
    case editOneOff(UUID)
    /// Edit… on a recurring row: the item editor (by item id).
    case editItem(UUID)
    /// The add menu's "Deadline…".
    case deadline

    var id: String {
        switch self {
        case let .bump(id): return "bump-\(id.uuidString)"
        case let .editOneOff(id): return "one-off-\(id.uuidString)"
        case let .editItem(id): return "item-\(id.uuidString)"
        case .deadline: return "deadline"
        }
    }
}
