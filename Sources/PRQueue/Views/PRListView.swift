import AppKit
import SwiftUI

struct PRListView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        let rows = state.visibleRows

        Group {
            if rows.isEmpty {
                emptyState
            } else if state.groupByRepo {
                List(selection: $state.selectedPRID) {
                    ForEach(state.groupedRows, id: \.repo) { group in
                        Section {
                            ForEach(group.rows) { row in
                                PRRowView(row: row).tag(row.id)
                            }
                        } header: {
                            HStack {
                                Text(group.repo)
                                Spacer()
                                Text("\(group.rows.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            } else {
                List(rows, selection: $state.selectedPRID) { row in
                    PRRowView(row: row).tag(row.id)
                }
            }
        }
        .navigationTitle(state.selectedLane.title)
        .navigationSubtitle("\(rows.count) pull request\(rows.count == 1 ? "" : "s")")
    }

    @ViewBuilder
    private var emptyState: some View {
        if state.isLoading && state.pullRequests.isEmpty {
            ContentUnavailableView {
                Label("Loading your queue", systemImage: "arrow.down.circle")
            } description: {
                Text("Reading pull requests from GitHub.")
            }
        } else if state.selectedLane == .needsYou {
            ContentUnavailableView {
                Label("Nothing needs you", systemImage: "checkmark.circle")
            } description: {
                Text("Every open request is a draft, a bot, already approved, blocked on its author, snoozed, or muted.")
            }
        } else {
            ContentUnavailableView {
                Label("This lane is empty", systemImage: "tray")
            } description: {
                Text(state.searchText.isEmpty ? "No pull requests here." : "No pull request matches the filter.")
            }
        }
    }
}

struct PRRowView: View {
    @Environment(AppState.self) private var state
    let row: TriagedPR

    private var pr: PullRequest { row.pullRequest }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ScorePill(score: row.score, isPinned: state.preferences.pinned.contains(pr.id))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(pr.title)
                    .lineLimit(2)
                    .font(.body)

                HStack(spacing: 6) {
                    CIStatusIcon(state: pr.ciState)
                        .font(.caption)
                    Text("\(pr.shortRepo) #\(pr.number)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(pr.authorLogin)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 4)
                    Text(SizeBucket(churn: pr.churn).rawValue)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .help("+\(pr.additions) / -\(pr.deletions) in \(pr.changedFiles) files")
                    if let reason = state.wokenByActivity[pr.id] {
                        Chip(text: reason, tint: .accentColor)
                            .help("This came back because \(reason) arrived.")
                    }
                    Text(pr.idleDays().asAgeText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .help("Idle for \(pr.idleDays().asAgeText). Opened \(pr.ageDays().asAgeText) ago.")
                }

                if !pr.requestedTeams.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(pr.requestedTeams.prefix(3), id: \.self) { team in
                            Chip(
                                text: team,
                                tint: state.preferences.priorityTeams.contains(team) ? .accentColor : .secondary
                            )
                        }
                        if pr.requestedTeams.count > 3 {
                            Chip(text: "+\(pr.requestedTeams.count - 3)")
                        }
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .contextMenu { PRActionsMenu(row: row) }
    }
}

/// Actions shared by the row context menu and the detail pane.
struct PRActionsMenu: View {
    @Environment(AppState.self) private var state
    let row: TriagedPR

    var body: some View {
        let pr = row.pullRequest

        Button("Open on GitHub") { openInBrowser(pr.url) }
        Button(state.preferences.pinned.contains(pr.id) ? "Unpin" : "Pin to top") {
            state.togglePin(pr.id)
        }

        Divider()

        if state.preferences.isSnoozed(pr.id) || state.isMutedUntilActivity(pr.id) {
            Button("Wake up now") { state.unsnooze(pr.id) }
        } else {
            Button("Mute until activity") { state.muteUntilActivity(pr) }
            Menu("Snooze") {
                Button("Until tomorrow") { snooze(days: 1) }
                Button("For 3 days") { snooze(days: 3) }
                Button("For a week") { snooze(days: 7) }
            }
        }

        Divider()

        if !pr.requestedTeams.isEmpty {
            Menu("Mute team") {
                ForEach(pr.requestedTeams, id: \.self) { team in
                    Button(state.preferences.mutedTeams.contains(team) ? "Unmute \(team)" : team) {
                        state.toggleMuteTeam(team)
                    }
                }
            }
            Menu("Priority team") {
                ForEach(pr.requestedTeams, id: \.self) { team in
                    Button(state.preferences.priorityTeams.contains(team) ? "Remove \(team)" : team) {
                        state.togglePriorityTeam(team)
                    }
                }
            }
        }
        Button(state.preferences.mutedRepos.contains(pr.repo) ? "Unmute \(pr.repo)" : "Mute \(pr.repo)") {
            state.toggleMuteRepo(pr.repo)
        }
        Button(state.preferences.mutedAuthors.contains(pr.authorLogin) ? "Unmute \(pr.authorLogin)" : "Mute \(pr.authorLogin)") {
            state.toggleMuteAuthor(pr.authorLogin)
        }

        Divider()
        Button("Copy link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(pr.url, forType: .string)
        }
    }

    private func snooze(days: Int) {
        state.snooze(row.id, until: Calendar.current.date(byAdding: .day, value: days, to: .now) ?? .now)
    }
}

func openInBrowser(_ url: String) {
    guard let link = URL(string: url) else { return }
    NSWorkspace.shared.open(link)
}
