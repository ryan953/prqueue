import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        let counts = state.countsByLane

        List(selection: $state.selectedLane) {
            Section("Queue") {
                ForEach(Lane.sidebarOrder) { lane in
                    let count = counts[lane] ?? 0
                    Label {
                        HStack {
                            Text(lane.title)
                            Spacer()
                            Text("\(count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(count == 0 ? .tertiary : .secondary)
                        }
                    } icon: {
                        Image(systemName: lane.systemImage)
                            .foregroundStyle(lane.tint)
                    }
                    .tag(lane)
                }
            }

            Section("Repositories") {
                ForEach(state.repoCounts, id: \.repo) { entry in
                    let muted = state.preferences.mutedRepos.contains(entry.repo)
                    HStack {
                        Text(entry.repo)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .foregroundStyle(muted ? .tertiary : .primary)
                            .strikethrough(muted)
                        Spacer()
                        Text("\(entry.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .help(muted ? "Muted. Click to unmute." : "Click to mute this repository.")
                    .onTapGesture { state.toggleMuteRepo(entry.repo) }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if let needs = counts[.needsYou], let total = totalReviewRequests(counts) {
                VStack(alignment: .leading, spacing: 2) {
                    Divider()
                    Text("\(needs) of \(total) review requests need you")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
            }
        }
    }

    /// Every lane a review request can land in, so the headline compares like
    /// with like and never counts the viewer's own PRs.
    private func totalReviewRequests(_ counts: [Lane: Int]) -> Int? {
        let lanes: [Lane] = [.needsYou, .blockedOnAuthor, .bots, .approved, .drafts, .snoozed, .muted]
        return lanes.reduce(0) { $0 + (counts[$1] ?? 0) }
    }
}
