import Foundation

/// Tunable rule weights. Every one is shown in Settings, so the ordering is
/// never a black box.
struct Weights: Codable, Sendable, Equatable {
    var directRequest = 50
    var reReviewAfterPush = 40
    var priorityTeam = 25
    var freshActivity = 12
    var aging = 15
    var quickWin = 10
    var largeDiff = -12
    var manyReviewers = -10
    var longIdle = -15
    var myPRReadyToMerge = 45
    var myPRFailingChecks = 35

    static let `default` = Weights()
}

/// Everything the user controls, saved between runs.
struct Preferences: Codable, Sendable, Equatable {
    var mutedTeams: Set<String> = []
    var mutedRepos: Set<String> = []
    var mutedAuthors: Set<String> = []
    /// Teams whose reviews the user actually cares about.
    var priorityTeams: Set<String> = []
    /// PR id to the moment it should come back.
    var snoozedUntil: [String: Date] = [:]
    /// PR id to the activity it had when it was muted. It stays hidden while
    /// its activity still matches, and wakes as soon as anything happens.
    var mutedUntilActivity: [String: ActivitySnapshot] = [:]
    var pinned: Set<String> = []
    var weights: Weights = .default
    /// A pull request idle this long is treated as abandoned, not queued.
    var staleDays: Int = 60

    /// Minutes between automatic refreshes. Zero turns it off.
    var refreshMinutes: Int = 10

    static let empty = Preferences()

    /// True while the pull request has had no activity since it was muted.
    func isQuietSinceMute(_ pr: PullRequest) -> Bool {
        guard let saved = mutedUntilActivity[pr.id] else { return false }
        return saved == pr.activity
    }

    func isSnoozed(_ id: String, now: Date = .now) -> Bool {
        guard let until = snoozedUntil[id] else { return false }
        return until > now
    }

    /// A PR is muted when its repo, its author, or every team that asked for
    /// it is muted. A direct request to the viewer is never muted.
    func isMuted(_ pr: PullRequest, viewer: String) -> Bool {
        if pr.requestedUsers.contains(viewer) { return false }
        if mutedRepos.contains(pr.repo) { return true }
        if mutedAuthors.contains(pr.authorLogin) { return true }
        if !pr.requestedTeams.isEmpty, pr.requestedTeams.allSatisfy(mutedTeams.contains) { return true }
        return false
    }
}

/// Reads and writes Preferences as JSON under Application Support. A plain
/// file keeps the state easy to inspect and to back up.
struct PreferencesStore: Sendable {
    let url: URL

    init(directoryName: String = "PRQueue") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.url = base.appendingPathComponent("preferences.json")
    }

    func load() -> Preferences {
        guard let data = try? Data(contentsOf: url) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Preferences.self, from: data)) ?? .empty
    }

    func save(_ preferences: Preferences) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(preferences) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
