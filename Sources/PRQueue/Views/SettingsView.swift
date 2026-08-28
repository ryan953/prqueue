import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            TeamsSettings()
                .tabItem { Label("Teams", systemImage: "person.3") }
            WeightsSettings()
                .tabItem { Label("Ranking", systemImage: "slider.horizontal.3") }
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 440)
    }
}

/// Muting teams is the strongest control, because most review requests arrive
/// through a team rather than by name.
private struct TeamsSettings: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Teams that request your review")
                .font(.headline)
            Text("Mute a team to move its pull requests out of the queue. Mark a team as priority to raise them.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(state.teamCounts, id: \.team) { entry in
                HStack {
                    Text("\(entry.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: 26, alignment: .trailing)
                    Text(entry.team)
                        .foregroundStyle(state.preferences.mutedTeams.contains(entry.team) ? .tertiary : .primary)
                        .strikethrough(state.preferences.mutedTeams.contains(entry.team))
                    Spacer()
                    Button(state.preferences.priorityTeams.contains(entry.team) ? "Priority" : "Make priority") {
                        state.togglePriorityTeam(entry.team)
                    }
                    .buttonStyle(.link)
                    Button(state.preferences.mutedTeams.contains(entry.team) ? "Unmute" : "Mute") {
                        state.toggleMuteTeam(entry.team)
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .padding()
    }
}

private struct WeightsSettings: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        Form {
            Section("Raise a pull request") {
                stepper("Asked for you by name", value: $state.preferences.weights.directRequest)
                stepper("New commits after your review", value: $state.preferences.weights.reReviewAfterPush)
                stepper("From a priority team", value: $state.preferences.weights.priorityTeam)
                stepper("Active in the last day", value: $state.preferences.weights.freshActivity)
                stepper("Open for more than a week", value: $state.preferences.weights.aging)
                stepper("Small diff", value: $state.preferences.weights.quickWin)
            }
            Section("Lower a pull request") {
                stepper("Large diff", value: $state.preferences.weights.largeDiff)
                stepper("Four or more reviewers asked", value: $state.preferences.weights.manyReviewers)
                stepper("No activity for over a month", value: $state.preferences.weights.longIdle)
            }
            Section {
                Button("Reset to defaults") { state.preferences.weights = .default }
            }
        }
        .formStyle(.grouped)
    }

    private func stepper(_ title: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: -100...100, step: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue > 0 ? "+\(value.wrappedValue)" : "\(value.wrappedValue)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct GeneralSettings: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        Form {
            Section("Account") {
                LabeledContent("Signed in as", value: state.viewer.isEmpty ? "unknown" : state.viewer)
                Text("The token comes from the gh command line tool. Run `gh auth login` to change it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Refresh") {
                Picker("Check GitHub every", selection: $state.preferences.refreshMinutes) {
                    Text("Never").tag(0)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                }
            }
            Section("Muted") {
                LabeledContent("Teams", value: "\(state.preferences.mutedTeams.count)")
                LabeledContent("Repositories", value: "\(state.preferences.mutedRepos.count)")
                LabeledContent("Authors", value: "\(state.preferences.mutedAuthors.count)")
                LabeledContent("Snoozed pull requests", value: "\(state.preferences.snoozedUntil.count)")
                LabeledContent("Muted until activity", value: "\(state.preferences.mutedUntilActivity.count)")
                Button("Clear all muting and snoozing") {
                    state.preferences.mutedTeams = []
                    state.preferences.mutedRepos = []
                    state.preferences.mutedAuthors = []
                    state.preferences.snoozedUntil = [:]
                    state.preferences.mutedUntilActivity = [:]
                }
            }
        }
        .formStyle(.grouped)
    }
}
