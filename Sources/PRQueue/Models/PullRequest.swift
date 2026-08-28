import Foundation

/// One pull request, flattened from the GitHub GraphQL response into the
/// shape the triage rules and the UI actually need.
struct PullRequest: Identifiable, Codable, Sendable, Hashable {
    var id: String { "\(repo)#\(number)" }

    let repo: String
    let number: Int
    let title: String
    let url: String
    let isDraft: Bool
    let isPrivate: Bool
    /// A pull request in an archived repository cannot be merged or reviewed,
    /// so it never reaches the queue.
    let isArchived: Bool
    let createdAt: Date
    let updatedAt: Date
    let additions: Int
    let deletions: Int
    let changedFiles: Int
    /// APPROVED, CHANGES_REQUESTED, REVIEW_REQUIRED, or nil.
    let reviewDecision: String?
    let authorLogin: String
    let authorIsBot: Bool
    /// Reviewers requested by login. Contains the viewer when the ask is direct.
    let requestedUsers: [String]
    /// Reviewer teams by slug. This is how most requests arrive.
    let requestedTeams: [String]
    /// The viewer's own most recent review on this PR, if any.
    let myReviewState: String?
    let myReviewAt: Date?
    /// SUCCESS, FAILURE, PENDING, ERROR, EXPECTED, or NONE when no checks ran.
    let ciState: String
    let lastCommitAt: Date?
    let commentCount: Int
    let reviewCount: Int
    let labels: [String]
    /// True when the viewer wrote the PR.
    let isMine: Bool

    /// Everything that counts as activity on a pull request: a push, a
    /// comment, a review, a check result, or any edit GitHub records.
    var activity: ActivitySnapshot {
        ActivitySnapshot(
            updatedAt: updatedAt,
            lastCommitAt: lastCommitAt,
            ciState: ciState,
            commentCount: commentCount,
            reviewCount: reviewCount
        )
    }

    var churn: Int { additions + deletions }
    var shortRepo: String {
        guard let slash = repo.firstIndex(of: "/") else { return repo }
        return String(repo[repo.index(after: slash)...])
    }
    var owner: String {
        guard let slash = repo.firstIndex(of: "/") else { return repo }
        return String(repo[..<slash])
    }

    func ageDays(now: Date = .now) -> Double {
        now.timeIntervalSince(createdAt) / 86_400
    }
    func idleDays(now: Date = .now) -> Double {
        now.timeIntervalSince(updatedAt) / 86_400
    }
    /// True when the viewer reviewed, and the author has pushed since.
    var hasNewCommitsSinceMyReview: Bool {
        guard let mine = myReviewAt, let commit = lastCommitAt else { return false }
        return commit > mine
    }
}

/// A short, human readable size bucket. Used for the queue's "quick win" hint.
enum SizeBucket: String, Sendable {
    case xs = "XS", s = "S", m = "M", l = "L", xl = "XL"

    init(churn: Int) {
        switch churn {
        case ..<50: self = .xs
        case ..<200: self = .s
        case ..<500: self = .m
        case ..<1500: self = .l
        default: self = .xl
        }
    }
}


/// A point-in-time picture of a pull request's activity. "Mute until
/// activity" saves one of these and compares against it on every refresh.
struct ActivitySnapshot: Codable, Sendable, Equatable, Hashable {
    let updatedAt: Date
    let lastCommitAt: Date?
    let ciState: String
    let commentCount: Int
    let reviewCount: Int

    /// A short reason for waking, so the user learns why it came back.
    func changeDescription(from old: ActivitySnapshot) -> String {
        if commentCount > old.commentCount {
            let added = commentCount - old.commentCount
            return "\(added) new comment\(added == 1 ? "" : "s")"
        }
        if reviewCount > old.reviewCount { return "a new review" }
        if lastCommitAt != old.lastCommitAt { return "new commits" }
        if ciState != old.ciState { return "checks are now \(ciState.lowercased())" }
        return "an update"
    }
}
