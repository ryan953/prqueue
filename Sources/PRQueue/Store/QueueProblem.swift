import Foundation

/// A failed refresh, described in terms of what the user can do about it.
struct QueueProblem: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case ghMissing
        case loggedOut
        case tokenRejected
        case rateLimited(resetAt: Date?)
        case offline
        case other
    }

    let kind: Kind
    let title: String
    let message: String
    /// A shell command that fixes the problem, when one exists.
    let fixCommand: String?
    /// The raw error, kept for the "details" disclosure and for bug reports.
    let detail: String

    /// True when the fix happens outside the app, so returning to the app is
    /// a good moment to try again.
    var isFixedOutsideApp: Bool {
        switch kind {
        case .ghMissing, .loggedOut, .tokenRejected: true
        case .rateLimited, .offline, .other: false
        }
    }

    init(_ error: Error) {
        detail = error.localizedDescription
        // gh reports its own API failures as text, so a rate limit met inside
        // gh is recognized by its message.
        let error: Error = if case GitHubAuthError.ghFailed(let text) = error,
            text.localizedCaseInsensitiveContains("rate limit") {
            GitHubClientError.rateLimited(resetAt: nil)
        } else {
            error
        }
        switch error {
        case GitHubAuthError.ghNotFound:
            kind = .ghMissing
            title = "The gh tool is not installed"
            message = "PR Queue reads your GitHub login from the gh command line tool. Install it, then log in."
            fixCommand = "brew install gh && gh auth login -h github.com"
        case GitHubAuthError.notLoggedIn, GitHubAuthError.noToken:
            kind = .loggedOut
            title = "Not logged in to GitHub"
            message = "gh has no GitHub login. Log in with gh, then try again."
            fixCommand = "gh auth login -h github.com"
        case GitHubClientError.unauthorized:
            kind = .tokenRejected
            title = "Your GitHub login has expired"
            message = "gh has a token, but GitHub no longer accepts it. Log in again with gh, then try again."
            fixCommand = "gh auth login -h github.com"
        case GitHubClientError.rateLimited(let resetAt):
            kind = .rateLimited(resetAt: resetAt)
            title = "GitHub rate limit reached"
            if let resetAt {
                message = "Your account used its hourly GitHub API budget. It resets at \(resetAt.formatted(date: .omitted, time: .shortened)). Other tools that use gh share this budget."
            } else {
                message = "Your account used its GitHub API budget. Other tools that use gh share this budget. Try again in a few minutes."
            }
            fixCommand = nil
        case let error as URLError where Self.offlineCodes.contains(error.code):
            kind = .offline
            title = "Cannot reach GitHub"
            message = "Check your network connection, then try again."
            fixCommand = nil
        case GitHubAuthError.ghFailed:
            kind = .other
            title = "gh failed"
            message = "gh could not give a token. Check the login with gh auth status."
            fixCommand = "gh auth status"
        default:
            kind = .other
            title = "Could not load your queue"
            message = "The refresh failed. See the details below."
            fixCommand = nil
        }
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
        .cannotConnectToHost, .timedOut, .dnsLookupFailed,
    ]
}
