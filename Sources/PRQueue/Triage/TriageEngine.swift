import Foundation

/// One rule that fired, kept so the UI can show why a PR sits where it does.
struct TriageReason: Identifiable, Sendable, Hashable {
    var id: String { label }
    let label: String
    let points: Int
}

/// The result of triage for a single PR.
struct TriagedPR: Identifiable, Sendable, Hashable {
    var id: String { pullRequest.id }
    let pullRequest: PullRequest
    let lane: Lane
    let score: Int
    let reasons: [TriageReason]
    /// Why the PR left the "Needs you" lane, when it did.
    let laneExplanation: String
}

/// Sorts the whole queue into lanes, then scores within a lane.
///
/// The lane answers "is this mine to do now?". The score only orders what is
/// left. Keeping those separate is what turns a flat list of review requests
/// into a queue.
struct TriageEngine: Sendable {
    let preferences: Preferences
    let viewer: String
    var now: Date = .now

    /// Pinning outranks every rule, so a pinned PR always sorts to the top.
    private static let pinBonus = 1_000

    func triage(_ pullRequests: [PullRequest]) -> [TriagedPR] {
        pullRequests
            .map(triage(_:))
            .sorted { left, right in
                if left.score != right.score { return left.score > right.score }
                return left.pullRequest.updatedAt > right.pullRequest.updatedAt
            }
    }

    func triage(_ pr: PullRequest) -> TriagedPR {
        let (lane, explanation) = lane(for: pr)
        let reasons = reasons(for: pr)
        let base = reasons.reduce(0) { $0 + $1.points }
        let score = base + (preferences.pinned.contains(pr.id) ? Self.pinBonus : 0)
        return TriagedPR(
            pullRequest: pr,
            lane: lane,
            score: score,
            reasons: reasons,
            laneExplanation: explanation
        )
    }

    // MARK: - Lane

    private func lane(for pr: PullRequest) -> (Lane, String) {
        if preferences.isSnoozed(pr.id, now: now) {
            let until = preferences.snoozedUntil[pr.id] ?? now
            return (.snoozed, "Snoozed until \(until.formatted(date: .abbreviated, time: .shortened)).")
        }
        if preferences.isQuietSinceMute(pr) {
            return (.snoozed, "Muted until something happens. No comment, review, push, or check result since you muted it.")
        }
        if pr.isMine {
            if pr.idleDays(now: now) > Double(preferences.staleDays) {
                return (.stale, "Your pull request, untouched for \(pr.idleDays(now: now).asAgeText).")
            }
            return (.mine, myPRExplanation(pr))
        }
        // A pin is an explicit promise to review, so it beats the filters below.
        if preferences.pinned.contains(pr.id) {
            return (.needsYou, "Pinned by you.")
        }
        if preferences.isMuted(pr, viewer: viewer) {
            return (.muted, mutedExplanation(pr))
        }
        if pr.isDraft {
            return (.drafts, "Still a draft, so the author is not asking yet.")
        }
        if pr.authorIsBot {
            return (.bots, "Written by \(pr.authorLogin), which is automation. Review these in a batch.")
        }
        if pr.reviewDecision == "APPROVED" {
            return (.approved, "Already approved by someone else, so it does not need you.")
        }
        if pr.reviewDecision == "CHANGES_REQUESTED" {
            return (.blockedOnAuthor, "Changes were requested. The author must act next.")
        }
        if pr.ciState == "FAILURE" || pr.ciState == "ERROR" {
            return (.blockedOnAuthor, "CI is failing. The author must fix it before a review helps.")
        }
        let idle = pr.idleDays(now: now)
        if idle > Double(preferences.staleDays) {
            return (.stale, "Nobody has touched it for \(idle.asAgeText). Treat it as abandoned, not queued.")
        }
        return (.needsYou, "Open, green, and waiting on a reviewer.")
    }

    private func myPRExplanation(_ pr: PullRequest) -> String {
        if pr.isDraft { return "Your draft. Nobody is waiting on it yet." }
        if pr.ciState == "FAILURE" || pr.ciState == "ERROR" { return "Your pull request, with failing checks." }
        if pr.reviewDecision == "CHANGES_REQUESTED" { return "Changes were requested. It is your turn." }
        if pr.reviewDecision == "APPROVED" { return "Approved and ready. You can merge it." }
        return "Your pull request, waiting on a reviewer."
    }

    private func mutedExplanation(_ pr: PullRequest) -> String {
        if preferences.mutedRepos.contains(pr.repo) { return "The repository \(pr.repo) is muted." }
        if preferences.mutedAuthors.contains(pr.authorLogin) { return "The author \(pr.authorLogin) is muted." }
        return "Every team that asked (\(pr.requestedTeams.joined(separator: ", "))) is muted."
    }

    // MARK: - Score

    private func reasons(for pr: PullRequest) -> [TriageReason] {
        let weights = preferences.weights
        var reasons: [TriageReason] = []

        func add(_ label: String, _ points: Int) {
            guard points != 0 else { return }
            reasons.append(TriageReason(label: label, points: points))
        }

        if pr.requestedUsers.contains(viewer) {
            add("Asked for you by name", weights.directRequest)
        }
        if pr.hasNewCommitsSinceMyReview {
            add("You reviewed it, and there are new commits", weights.reReviewAfterPush)
        }
        if !preferences.priorityTeams.isEmpty,
           pr.requestedTeams.contains(where: preferences.priorityTeams.contains) {
            let matched = pr.requestedTeams.filter(preferences.priorityTeams.contains)
            add("Priority team: \(matched.joined(separator: ", "))", weights.priorityTeam)
        }

        let idle = pr.idleDays(now: now)
        let age = pr.ageDays(now: now)
        if idle < 1 { add("Active in the last day", weights.freshActivity) }
        if idle > 30 { add("No activity for over a month", weights.longIdle) }
        // Aging only counts while the pull request is still alive. Without
        // this guard an abandoned pull request collects the aging bonus and
        // cancels its own idle penalty.
        if age > 7, idle < 14 { add("Open for more than a week, and still moving", weights.aging) }

        if pr.isMine {
            if pr.reviewDecision == "APPROVED", pr.ciState == "SUCCESS" {
                add("Approved and green, so you can merge it", weights.myPRReadyToMerge)
            }
            if pr.ciState == "FAILURE" || pr.ciState == "ERROR" {
                add("Your checks are failing", weights.myPRFailingChecks)
            }
            if pr.reviewDecision == "CHANGES_REQUESTED" {
                add("Changes were requested from you", weights.myPRFailingChecks)
            }
        }

        switch SizeBucket(churn: pr.churn) {
        case .xs: add("Small diff, quick to review", weights.quickWin)
        case .xl, .l: add("Large diff, needs a long session", weights.largeDiff)
        default: break
        }

        let reviewerCount = pr.requestedUsers.count + pr.requestedTeams.count
        if reviewerCount >= 4 {
            add("\(reviewerCount) reviewers asked, so it is not only yours", weights.manyReviewers)
        }
        return reasons
    }
}
