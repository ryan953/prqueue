import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    // MARK: Data
    private(set) var pullRequests: [PullRequest] = []
    private(set) var isLoading = false
    private(set) var lastError: String?
    private(set) var lastRefresh: Date?
    private(set) var viewer: String = ""

    // MARK: Selection and view options
    var selectedLane: Lane = .needsYou
    var selectedPRID: String?
    var searchText: String = ""
    var groupByRepo = false

    // MARK: Preferences
    var preferences: Preferences {
        didSet { if preferences != oldValue { store.save(preferences) } }
    }

    private let store = PreferencesStore()
    private var refreshTask: Task<Void, Never>?

    init() {
        self.preferences = store.load()
    }

    // MARK: - Derived

    var engine: TriageEngine {
        TriageEngine(preferences: preferences, viewer: viewer)
    }

    var triaged: [TriagedPR] { engine.triage(pullRequests) }

    var countsByLane: [Lane: Int] {
        triaged.reduce(into: [:]) { counts, item in counts[item.lane, default: 0] += 1 }
    }

    /// The rows shown in the middle column: one lane, filtered by the search box.
    var visibleRows: [TriagedPR] {
        let inLane = triaged.filter { $0.lane == selectedLane }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return inLane }
        return inLane.filter { row in
            let pr = row.pullRequest
            return pr.title.lowercased().contains(query)
                || pr.repo.lowercased().contains(query)
                || pr.authorLogin.lowercased().contains(query)
                || String(pr.number).contains(query)
                || pr.requestedTeams.contains { $0.lowercased().contains(query) }
        }
    }

    /// Rows grouped by repository, sorted by the best score in each group.
    var groupedRows: [(repo: String, rows: [TriagedPR])] {
        Dictionary(grouping: visibleRows, by: { $0.pullRequest.repo })
            .map { (repo: $0.key, rows: $0.value) }
            .sorted { left, right in
                let l = left.rows.first?.score ?? 0
                let r = right.rows.first?.score ?? 0
                if l != r { return l > r }
                return left.repo < right.repo
            }
    }

    var selectedRow: TriagedPR? {
        guard let selectedPRID else { return nil }
        return triaged.first { $0.id == selectedPRID }
    }

    /// Every team that has asked for a review, with how often. Drives the
    /// muting UI, which is the highest leverage control in the app.
    var teamCounts: [(team: String, count: Int)] {
        var counts: [String: Int] = [:]
        for pr in pullRequests where !pr.isMine {
            for team in pr.requestedTeams { counts[team, default: 0] += 1 }
        }
        return counts.map { (team: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.team < $1.team }
    }

    var repoCounts: [(repo: String, count: Int)] {
        var counts: [String: Int] = [:]
        for pr in pullRequests { counts[pr.repo, default: 0] += 1 }
        return counts.map { (repo: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.repo < $1.repo }
    }

    // MARK: - Actions

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        lastError = nil
        do {
            let token = try GitHubAuth.token()
            let login = viewer.isEmpty ? try GitHubAuth.viewerLogin() : viewer
            viewer = login
            let client = GitHubClient(token: token, viewer: login)
            pullRequests = try await client.fetchQueue()
            lastRefresh = .now
            pruneExpiredSnoozes()
            wakeChangedPullRequests()
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
    }

    func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let minutes = self.preferences.refreshMinutes
                guard minutes > 0 else {
                    try? await Task.sleep(for: .seconds(60))
                    continue
                }
                try? await Task.sleep(for: .seconds(Double(minutes) * 60))
                guard !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    func snooze(_ id: String, until date: Date) {
        preferences.snoozedUntil[id] = date
    }

    func unsnooze(_ id: String) {
        preferences.snoozedUntil.removeValue(forKey: id)
        preferences.mutedUntilActivity.removeValue(forKey: id)
    }

    /// Hides a pull request until it changes in any way.
    func muteUntilActivity(_ pr: PullRequest) {
        preferences.mutedUntilActivity[pr.id] = pr.activity
        preferences.snoozedUntil.removeValue(forKey: pr.id)
    }

    /// True when the pull request is hidden waiting for activity.
    func isMutedUntilActivity(_ id: String) -> Bool {
        preferences.mutedUntilActivity[id] != nil
    }

    /// Pull requests that woke on the most recent refresh, with the reason.
    private(set) var wokenByActivity: [String: String] = [:]

    func togglePin(_ id: String) {
        if preferences.pinned.contains(id) {
            preferences.pinned.remove(id)
        } else {
            preferences.pinned.insert(id)
        }
    }

    func toggleMuteTeam(_ team: String) {
        if preferences.mutedTeams.contains(team) {
            preferences.mutedTeams.remove(team)
        } else {
            preferences.mutedTeams.insert(team)
            preferences.priorityTeams.remove(team)
        }
    }

    func togglePriorityTeam(_ team: String) {
        if preferences.priorityTeams.contains(team) {
            preferences.priorityTeams.remove(team)
        } else {
            preferences.priorityTeams.insert(team)
            preferences.mutedTeams.remove(team)
        }
    }

    func toggleMuteRepo(_ repo: String) {
        if preferences.mutedRepos.contains(repo) {
            preferences.mutedRepos.remove(repo)
        } else {
            preferences.mutedRepos.insert(repo)
        }
    }

    func toggleMuteAuthor(_ author: String) {
        if preferences.mutedAuthors.contains(author) {
            preferences.mutedAuthors.remove(author)
        } else {
            preferences.mutedAuthors.insert(author)
        }
    }

    /// Clears the mute on every pull request that has changed since it was
    /// muted, and remembers why, so the reason can be shown.
    private func wakeChangedPullRequests() {
        var woken: [String: String] = [:]
        var remaining = preferences.mutedUntilActivity
        let known = Set(pullRequests.map(\.id))
        for pr in pullRequests {
            guard let saved = remaining[pr.id] else { continue }
            if saved != pr.activity {
                woken[pr.id] = pr.activity.changeDescription(from: saved)
                remaining.removeValue(forKey: pr.id)
            }
        }
        // Forget pull requests that closed, so the file does not grow forever.
        remaining = remaining.filter { known.contains($0.key) }
        wokenByActivity = woken
        if remaining != preferences.mutedUntilActivity {
            preferences.mutedUntilActivity = remaining
        }
    }

    /// Drops snoozes that have run out, to keep the saved file small.
    private func pruneExpiredSnoozes() {
        let now = Date.now
        preferences.snoozedUntil = preferences.snoozedUntil.filter { $0.value > now }
    }
}
