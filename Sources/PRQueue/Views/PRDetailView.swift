import AppKit
import SwiftUI

struct PRDetailView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let row = state.selectedRow {
            PRDetailContent(row: row)
        } else {
            ContentUnavailableView {
                Label("No pull request selected", systemImage: "sidebar.right")
            } description: {
                Text("Select a pull request to see why it is in this lane.")
            }
        }
    }
}

private struct PRDetailContent: View {
    @Environment(AppState.self) private var state
    let row: TriagedPR

    private var pr: PullRequest { row.pullRequest }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                laneCard
                facts
                if !row.reasons.isEmpty {
                    Divider()
                    scoreBreakdown
                }
                if !pr.requestedTeams.isEmpty {
                    Divider()
                    teams
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .navigationTitle("\(pr.shortRepo) #\(pr.number)")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    state.togglePin(pr.id)
                } label: {
                    Label(
                        "Pin",
                        systemImage: state.preferences.pinned.contains(pr.id) ? "pin.fill" : "pin"
                    )
                }
                .help("Pin to the top of Needs you")

                Menu {
                    PRActionsMenu(row: row)
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }

                Button {
                    openInBrowser(pr.url)
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                }
                .keyboardShortcut(.return, modifiers: [])
                .help("Open on GitHub")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pr.title)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
            HStack(spacing: 8) {
                ScorePill(score: row.score, isPinned: state.preferences.pinned.contains(pr.id))
                Text(pr.repo)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                Text("by \(pr.authorLogin)")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var laneCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: row.lane.systemImage)
                .foregroundStyle(row.lane.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.lane.title).font(.callout.weight(.medium))
                Text(row.laneExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(row.lane.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var facts: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
            GridRow {
                factLabel("Checks")
                HStack(spacing: 5) {
                    CIStatusIcon(state: pr.ciState)
                    Text(pr.ciState.capitalized).font(.callout)
                }
            }
            GridRow {
                factLabel("Decision")
                Text(decisionText).font(.callout)
            }
            GridRow {
                factLabel("Size")
                Text("+\(pr.additions) / -\(pr.deletions) in \(pr.changedFiles) file\(pr.changedFiles == 1 ? "" : "s")")
                    .font(.callout.monospacedDigit())
            }
            GridRow {
                factLabel("Opened")
                Text("\(pr.ageDays().asAgeText) ago").font(.callout)
            }
            GridRow {
                factLabel("Last change")
                Text("\(pr.idleDays().asAgeText) ago").font(.callout)
            }
            if let myState = pr.myReviewState {
                GridRow {
                    factLabel("Your review")
                    Text(myState.capitalized + (pr.hasNewCommitsSinceMyReview ? ", then new commits arrived" : ""))
                        .font(.callout)
                }
            }
            if !pr.labels.isEmpty {
                GridRow {
                    factLabel("Labels")
                    Text(pr.labels.joined(separator: ", "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func factLabel(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.leading)
    }

    private var decisionText: String {
        switch pr.reviewDecision {
        case "APPROVED": "Approved"
        case "CHANGES_REQUESTED": "Changes requested"
        case "REVIEW_REQUIRED": "Review required"
        default: "None"
        }
    }

    private var scoreBreakdown: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Why it is ranked here")
                .font(.callout.weight(.medium))
            ForEach(row.reasons) { reason in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(reason.points > 0 ? "+\(reason.points)" : "\(reason.points)")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(reason.points > 0 ? .green : .red)
                        .frame(width: 34, alignment: .trailing)
                    Text(reason.label)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if state.preferences.pinned.contains(pr.id) {
                HStack(spacing: 8) {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(width: 34, alignment: .trailing)
                    Text("Pinned, so it always sorts first").font(.caption)
                }
            }
        }
    }

    private var teams: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Teams that asked")
                .font(.callout.weight(.medium))
            ForEach(pr.requestedTeams, id: \.self) { team in
                HStack {
                    Text(team).font(.caption)
                    Spacer()
                    Button(state.preferences.priorityTeams.contains(team) ? "Priority" : "Make priority") {
                        state.togglePriorityTeam(team)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    Button(state.preferences.mutedTeams.contains(team) ? "Unmute" : "Mute") {
                        state.toggleMuteTeam(team)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        }
    }
}
