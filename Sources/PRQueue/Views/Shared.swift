import SwiftUI

/// A small rounded label used for teams, sizes, and lane hints.
struct Chip: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}

/// Shows the CI rollup as an icon, because the state is glanceable and the
/// word is not.
struct CIStatusIcon: View {
    let state: String

    private var appearance: (name: String, color: Color, help: String) {
        switch state {
        case "SUCCESS": ("checkmark.circle.fill", .green, "Checks passed")
        case "FAILURE", "ERROR": ("xmark.circle.fill", .red, "Checks failed")
        case "PENDING", "EXPECTED": ("clock.fill", .orange, "Checks running")
        default: ("minus.circle", .secondary, "No checks")
        }
    }

    var body: some View {
        Image(systemName: appearance.name)
            .foregroundStyle(appearance.color)
            .help(appearance.help)
            .accessibilityLabel(appearance.help)
    }
}

/// The triage score, shown so the ordering can be questioned.
struct ScorePill: View {
    let score: Int
    let isPinned: Bool

    var body: some View {
        HStack(spacing: 2) {
            if isPinned { Image(systemName: "pin.fill").font(.system(size: 8)) }
            Text(isPinned ? "pin" : "\(score)")
        }
        .font(.caption.monospacedDigit().weight(.medium))
        .frame(minWidth: 34)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
        .foregroundStyle(color)
    }

    private var color: Color {
        if isPinned { return .orange }
        return switch score {
        case 40...: .accentColor
        case 10..<40: .primary
        default: .secondary
        }
    }
}

extension Double {
    /// Formats an age in days the way a reviewer reads it: hours, then days.
    var asAgeText: String {
        if self < 1 / 24 { return "now" }
        if self < 1 { return "\(Int(self * 24))h" }
        if self < 60 { return "\(Int(self))d" }
        return "\(Int(self / 30))mo"
    }
}
