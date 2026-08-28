import Foundation
import Testing
@testable import PRQueue

/// A pull request builder, so each test states only the fields it cares about.
private func makePR(
    repo: String = "getsentry/sentry",
    number: Int = 1,
    isDraft: Bool = false,
    ageDays: Double = 1,
    idleDays: Double = 0.5,
    additions: Int = 10,
    deletions: Int = 10,
    reviewDecision: String? = "REVIEW_REQUIRED",
    author: String = "someone",
    isBot: Bool = false,
    requestedUsers: [String] = [],
    requestedTeams: [String] = ["app-frontend"],
    myReviewState: String? = nil,
    myReviewAgoDays: Double? = nil,
    lastCommitAgoDays: Double? = nil,
    ci: String = "SUCCESS",
    commentCount: Int = 0,
    reviewCount: Int = 0,
    isArchived: Bool = false,
    isMine: Bool = false,
    now: Date = Date(timeIntervalSince1970: 1_800_000_000)
) -> PullRequest {
    PullRequest(
        repo: repo,
        number: number,
        title: "title",
        url: "https://github.com/\(repo)/pull/\(number)",
        isDraft: isDraft,
        isPrivate: false,
        isArchived: isArchived,
        createdAt: now.addingTimeInterval(-ageDays * 86_400),
        updatedAt: now.addingTimeInterval(-idleDays * 86_400),
        additions: additions,
        deletions: deletions,
        changedFiles: 3,
        reviewDecision: reviewDecision,
        authorLogin: author,
        authorIsBot: isBot,
        requestedUsers: requestedUsers,
        requestedTeams: requestedTeams,
        myReviewState: myReviewState,
        myReviewAt: myReviewAgoDays.map { now.addingTimeInterval(-$0 * 86_400) },
        ciState: ci,
        lastCommitAt: lastCommitAgoDays.map { now.addingTimeInterval(-$0 * 86_400) },
        commentCount: commentCount,
        reviewCount: reviewCount,
        labels: [],
        isMine: isMine
    )
}

private let testNow = Date(timeIntervalSince1970: 1_800_000_000)

private func engine(_ preferences: Preferences = .empty) -> TriageEngine {
    TriageEngine(preferences: preferences, viewer: "ryan953", now: testNow)
}

// MARK: - Lanes

@Suite("Lane assignment")
struct LaneTests {
    @Test("A green, open, human pull request needs the viewer")
    func needsYou() {
        #expect(engine().triage(makePR()).lane == .needsYou)
    }

    @Test("Drafts, bots, approvals, and failing checks all leave the queue")
    func lanesThatRemoveWork() {
        #expect(engine().triage(makePR(isDraft: true)).lane == .drafts)
        #expect(engine().triage(makePR(author: "dependabot", isBot: true)).lane == .bots)
        #expect(engine().triage(makePR(reviewDecision: "APPROVED")).lane == .approved)
        #expect(engine().triage(makePR(reviewDecision: "CHANGES_REQUESTED")).lane == .blockedOnAuthor)
        #expect(engine().triage(makePR(ci: "FAILURE")).lane == .blockedOnAuthor)
    }

    @Test("A pull request idle past the threshold is stale, not queued")
    func staleLane() {
        #expect(engine().triage(makePR(ageDays: 200, idleDays: 90)).lane == .stale)
        #expect(engine().triage(makePR(ageDays: 200, idleDays: 30)).lane == .needsYou)
    }

    @Test("The viewer's own pull requests go to their own lane")
    func ownLane() {
        #expect(engine().triage(makePR(ci: "FAILURE", isMine: true)).lane == .mine)
    }

    @Test("Muting a team removes its pull requests")
    func mutedTeam() {
        var preferences = Preferences.empty
        preferences.mutedTeams = ["app-frontend"]
        #expect(engine(preferences).triage(makePR(requestedTeams: ["app-frontend"])).lane == .muted)
        // A pull request asking two teams survives while one is unmuted.
        #expect(engine(preferences).triage(makePR(requestedTeams: ["app-frontend", "seer"])).lane == .needsYou)
    }

    @Test("A direct request by name is never muted")
    func directRequestBeatsMuting() {
        var preferences = Preferences.empty
        preferences.mutedTeams = ["app-frontend"]
        preferences.mutedRepos = ["getsentry/sentry"]
        let pr = makePR(requestedUsers: ["ryan953"], requestedTeams: ["app-frontend"])
        #expect(engine(preferences).triage(pr).lane == .needsYou)
    }

    @Test("Snoozing hides a pull request until its date passes")
    func snooze() {
        var preferences = Preferences.empty
        let pr = makePR()
        preferences.snoozedUntil[pr.id] = testNow.addingTimeInterval(3_600)
        #expect(engine(preferences).triage(pr).lane == .snoozed)

        preferences.snoozedUntil[pr.id] = testNow.addingTimeInterval(-3_600)
        #expect(engine(preferences).triage(pr).lane == .needsYou)
    }

    @Test("A pin overrides muting and drafts")
    func pinWins() {
        var preferences = Preferences.empty
        preferences.mutedTeams = ["app-frontend"]
        let pr = makePR(isDraft: true)
        preferences.pinned = [pr.id]
        #expect(engine(preferences).triage(pr).lane == .needsYou)
    }
}

// MARK: - Score

@Suite("Ranking")
struct ScoreTests {
    /// The bug this guards: the "open over a week" bonus used to cancel the
    /// "idle over a month" penalty, so a months-dead pull request outranked a
    /// live one.
    @Test("A live pull request outranks an old, idle one")
    func liveBeatsAbandoned() {
        let live = engine().triage(makePR(number: 1, ageDays: 0.5, idleDays: 0.1, additions: 400, deletions: 400))
        let abandoned = engine().triage(makePR(number: 2, ageDays: 200, idleDays: 45, additions: 5, deletions: 5))
        #expect(live.score > abandoned.score)
    }

    @Test("The aging bonus needs recent activity")
    func agingNeedsLife() {
        let moving = engine().triage(makePR(ageDays: 30, idleDays: 2))
        let stalled = engine().triage(makePR(ageDays: 30, idleDays: 20))
        #expect(moving.reasons.contains { $0.label.contains("still moving") })
        #expect(!stalled.reasons.contains { $0.label.contains("still moving") })
    }

    @Test("A request by name outranks a team request")
    func directBeatsTeam() {
        let direct = engine().triage(makePR(number: 1, requestedUsers: ["ryan953"]))
        let team = engine().triage(makePR(number: 2))
        #expect(direct.score > team.score)
    }

    @Test("New commits after the viewer's review raise the pull request")
    func reReview() {
        let pr = makePR(myReviewState: "COMMENTED", myReviewAgoDays: 3, lastCommitAgoDays: 1)
        #expect(pr.hasNewCommitsSinceMyReview)
        #expect(engine().triage(pr).reasons.contains { $0.label.contains("new commits") })
    }

    @Test("A pinned pull request sorts above everything else")
    func pinSortsFirst() {
        var preferences = Preferences.empty
        let pinned = makePR(number: 1, ageDays: 100, idleDays: 40)
        let hot = makePR(number: 2, idleDays: 0.1, requestedUsers: ["ryan953"])
        preferences.pinned = [pinned.id]
        let ranked = engine(preferences).triage([pinned, hot])
        #expect(ranked.first?.id == pinned.id)
    }

    @Test("A priority team lifts a pull request over an ordinary one")
    func priorityTeam() {
        var preferences = Preferences.empty
        preferences.priorityTeams = ["seer"]
        let priority = engine(preferences).triage(makePR(number: 1, requestedTeams: ["seer"]))
        let ordinary = engine(preferences).triage(makePR(number: 2, requestedTeams: ["other"]))
        #expect(priority.score > ordinary.score)
    }

    @Test("Own pull requests rank by what blocks them")
    func ownPRSignals() {
        let ready = engine().triage(makePR(number: 1, reviewDecision: "APPROVED", isMine: true))
        let broken = engine().triage(makePR(number: 2, ci: "FAILURE", isMine: true))
        let waiting = engine().triage(makePR(number: 3, isMine: true))
        #expect(ready.score > waiting.score)
        #expect(broken.score > waiting.score)
    }
}

// MARK: - Parsing

@Suite("Bot detection")
struct BotTests {
    @Test("Known automation logins are treated as bots")
    func knownBots() {
        #expect(PullRequest.looksLikeBot(login: "dependabot", typename: "User"))
        #expect(PullRequest.looksLikeBot(login: "getsantry[bot]", typename: "User"))
        #expect(PullRequest.looksLikeBot(login: "anything", typename: "Bot"))
        #expect(!PullRequest.looksLikeBot(login: "ryan953", typename: "User"))
        #expect(!PullRequest.looksLikeBot(login: "evanpurkhiser", typename: "User"))
    }
}


// MARK: - Mute until activity

@Suite("Mute until activity")
struct MuteUntilActivityTests {
    /// Mutes a pull request, then returns the engine result for a changed copy.
    private func laneAfterMuting(_ original: PullRequest, then changed: PullRequest) -> Lane {
        var preferences = Preferences.empty
        preferences.mutedUntilActivity[original.id] = original.activity
        return engine(preferences).triage(changed).lane
    }

    @Test("A muted pull request stays hidden while nothing happens")
    func quietStaysMuted() {
        let pr = makePR()
        #expect(laneAfterMuting(pr, then: pr) == .snoozed)
    }

    @Test("A new comment wakes it")
    func commentWakes() {
        let before = makePR(commentCount: 2)
        let after = makePR(commentCount: 3)
        #expect(laneAfterMuting(before, then: after) == .needsYou)
    }

    @Test("A new review wakes it")
    func reviewWakes() {
        let before = makePR(reviewCount: 0)
        let after = makePR(reviewCount: 1)
        #expect(laneAfterMuting(before, then: after) == .needsYou)
    }

    @Test("A check result wakes it")
    func checksWake() {
        let before = makePR(ci: "PENDING")
        let after = makePR(ci: "SUCCESS")
        #expect(laneAfterMuting(before, then: after) == .needsYou)
    }

    @Test("A new push wakes it")
    func pushWakes() {
        let before = makePR(lastCommitAgoDays: 5)
        let after = makePR(lastCommitAgoDays: 1)
        #expect(laneAfterMuting(before, then: after) == .needsYou)
    }

    @Test("An edit that bumps updatedAt wakes it")
    func updateWakes() {
        let before = makePR(idleDays: 5)
        let after = makePR(idleDays: 0.2)
        #expect(laneAfterMuting(before, then: after) == .needsYou)
    }

    @Test("Muting beats every lane except a timed snooze and a pin")
    func precedence() {
        let pr = makePR(ci: "FAILURE")
        // Without the mute this would be blocked on its author.
        #expect(engine().triage(pr).lane == .blockedOnAuthor)
        #expect(laneAfterMuting(pr, then: pr) == .snoozed)
    }

    @Test("The wake reason names what actually changed")
    func reasonText() {
        let before = makePR(commentCount: 1)
        #expect(makePR(commentCount: 3).activity.changeDescription(from: before.activity) == "2 new comments")
        #expect(makePR(commentCount: 2).activity.changeDescription(from: before.activity) == "1 new comment")
        #expect(makePR(ci: "FAILURE", commentCount: 1).activity.changeDescription(from: before.activity) == "checks are now failure")
        #expect(makePR(commentCount: 1, reviewCount: 1).activity.changeDescription(from: before.activity) == "a new review")
    }
}
