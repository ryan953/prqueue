import Foundation
import Testing
@testable import PRQueue

struct HTTPClassificationTests {
    @Test func unauthorizedIsItsOwnCase() {
        let error = GitHubClientError.from(status: 401, headers: [:], body: #"{"message":"Bad credentials"}"#)
        #expect(error == .unauthorized)
    }

    @Test func forbiddenWithSpentBudgetIsARateLimit() {
        let error = GitHubClientError.from(
            status: 403,
            headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1800000000"],
            body: "{}"
        )
        #expect(error == .rateLimited(resetAt: Date(timeIntervalSince1970: 1_800_000_000)))
    }

    @Test func secondaryRateLimitIsFoundFromTheBody() {
        let error = GitHubClientError.from(
            status: 403,
            headers: [:],
            body: #"{"message":"You have exceeded a secondary rate limit."}"#
        )
        #expect(error == .rateLimited(resetAt: nil))
    }

    @Test func plainForbiddenStaysAnHTTPError() {
        let error = GitHubClientError.from(status: 403, headers: ["x-ratelimit-remaining": "4000"], body: "nope")
        #expect(error == .http(403, "nope"))
    }
}

struct QueueProblemTests {
    @Test func loggedOutOffersLogin() {
        let problem = QueueProblem(GitHubAuthError.notLoggedIn)
        #expect(problem.kind == .loggedOut)
        #expect(problem.fixCommand == "gh auth login -h github.com")
        #expect(problem.isFixedOutsideApp)
    }

    @Test func rejectedTokenOffersLogin() {
        let problem = QueueProblem(GitHubClientError.unauthorized)
        #expect(problem.kind == .tokenRejected)
        #expect(problem.fixCommand == "gh auth login -h github.com")
        #expect(problem.isFixedOutsideApp)
    }

    @Test func missingGhOffersInstall() {
        let problem = QueueProblem(GitHubAuthError.ghNotFound)
        #expect(problem.kind == .ghMissing)
        #expect(problem.fixCommand?.hasPrefix("brew install gh") == true)
    }

    @Test func rateLimitHasNoCommandAndWaitsForTheUser() {
        let problem = QueueProblem(GitHubClientError.rateLimited(resetAt: nil))
        #expect(problem.fixCommand == nil)
        #expect(!problem.isFixedOutsideApp)
    }

    @Test func rateLimitReportedByGhIsARateLimit() {
        let problem = QueueProblem(GitHubAuthError.ghFailed("gh: API rate limit exceeded for user ID 1. (HTTP 403)"))
        #expect(problem.kind == .rateLimited(resetAt: nil))
    }

    @Test func networkErrorsAreOffline() {
        let problem = QueueProblem(URLError(.notConnectedToInternet))
        #expect(problem.kind == .offline)
    }

    @Test func unknownErrorsKeepTheRawDetail() {
        let problem = QueueProblem(GitHubClientError.graphQL(["Something broke"]))
        #expect(problem.kind == .other)
        #expect(problem.detail.contains("Something broke"))
    }
}
