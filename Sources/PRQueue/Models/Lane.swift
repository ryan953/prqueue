import SwiftUI

/// Each PR goes into exactly one lane. The lane answers "is this mine to do
/// right now?" before any score is compared.
enum Lane: String, CaseIterable, Identifiable, Codable, Sendable {
    case needsYou
    case mine
    case blockedOnAuthor
    case bots
    case approved
    case drafts
    case stale
    case snoozed
    case muted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .needsYou: "Needs you"
        case .mine: "My PRs"
        case .blockedOnAuthor: "Blocked on author"
        case .bots: "Bots"
        case .approved: "Already approved"
        case .drafts: "Drafts"
        case .stale: "Stale"
        case .snoozed: "Snoozed"
        case .muted: "Muted"
        }
    }

    var systemImage: String {
        switch self {
        case .needsYou: "person.crop.circle.badge.exclamationmark"
        case .mine: "arrow.up.circle"
        case .blockedOnAuthor: "exclamationmark.triangle"
        case .bots: "gearshape.2"
        case .approved: "checkmark.seal"
        case .drafts: "pencil.line"
        case .stale: "hourglass.tophalf.filled"
        case .snoozed: "moon.zzz"
        case .muted: "speaker.slash"
        }
    }

    var tint: Color {
        switch self {
        case .needsYou: .accentColor
        case .mine: .purple
        case .blockedOnAuthor: .orange
        case .bots: .secondary
        case .approved: .green
        case .drafts: .secondary
        case .stale: .brown
        case .snoozed: .indigo
        case .muted: .secondary
        }
    }

    /// Lanes shown in the sidebar, in order.
    static var sidebarOrder: [Lane] {
        [.needsYou, .mine, .blockedOnAuthor, .bots, .approved, .drafts, .stale, .snoozed, .muted]
    }
}
