import Foundation

enum GitHubClientError: LocalizedError, Equatable {
    case unauthorized
    case rateLimited(resetAt: Date?)
    case http(Int, String)
    case graphQL([String])
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "GitHub rejected the token from gh (HTTP 401)."
        case .rateLimited(let resetAt):
            if let resetAt {
                "GitHub rate limit reached. It resets at \(resetAt.formatted(date: .omitted, time: .shortened))."
            } else {
                "GitHub rate limit reached."
            }
        case .http(let code, let body):
            "GitHub returned HTTP \(code): \(body.prefix(240))"
        case .graphQL(let messages):
            "GitHub GraphQL error: \(messages.joined(separator: "; "))"
        case .emptyResponse:
            "GitHub returned no data."
        }
    }

    /// Turns a failed HTTP response into the case the UI can act on. GitHub
    /// signals rate limits with 403 or 429, and only the headers or body tell
    /// them apart from a permission error.
    static func from(status: Int, headers: [AnyHashable: Any], body: String) -> GitHubClientError {
        if status == 401 { return .unauthorized }
        func header(_ name: String) -> String? {
            headers.first { ($0.key as? String)?.lowercased() == name }?.value as? String
        }
        let exhausted = header("x-ratelimit-remaining") == "0"
            || body.localizedCaseInsensitiveContains("rate limit")
        if status == 429 || (status == 403 && exhausted) {
            let reset = header("x-ratelimit-reset")
                .flatMap(TimeInterval.init)
                .map(Date.init(timeIntervalSince1970:))
            return .rateLimited(resetAt: reset)
        }
        return .http(status, body)
    }
}

/// Fetches the two lists that make up the queue: PRs waiting on the viewer's
/// review, and PRs the viewer wrote.
struct GitHubClient: Sendable {
    let token: String
    let viewer: String

    private static let endpoint = URL(string: "https://api.github.com/graphql")!
    private static let pageSize = 25

    private static let fragment = """
    fragment prFields on PullRequest {
      number title url isDraft createdAt updatedAt additions deletions changedFiles reviewDecision
      author { login __typename }
      repository { nameWithOwner isPrivate isArchived }
      reviewRequests(first: 30) {
        nodes { requestedReviewer { __typename ... on User { login } ... on Team { slug } } }
      }
      reviews(last: 30) { totalCount nodes { author { login } state submittedAt } }
      comments { totalCount }
      commits(last: 1) { nodes { commit { committedDate statusCheckRollup { state } } } }
      labels(first: 15) { nodes { name } }
    }
    """

    /// Fetches both lists concurrently and merges them, preferring the "mine"
    /// copy when a PR appears in both.
    func fetchQueue() async throws -> [PullRequest] {
        async let reviewing = fetchAllPages(
            search: "is:open is:pr review-requested:\(viewer) archived:false",
            isMine: false
        )
        async let authored = fetchAllPages(
            search: "is:open is:pr author:\(viewer) archived:false",
            isMine: true
        )

        var byID: [String: PullRequest] = [:]
        for pr in try await reviewing { byID[pr.id] = pr }
        for pr in try await authored { byID[pr.id] = pr }
        return Array(byID.values)
    }

    private func fetchAllPages(search: String, isMine: Bool) async throws -> [PullRequest] {
        var cursor: String?
        var collected: [PullRequest] = []
        repeat {
            let page = try await fetchPage(search: search, after: cursor)
            collected += page.nodes
                .compactMap { PullRequest(node: $0, viewer: viewer, isMine: isMine) }
                .filter { !$0.isArchived }
            cursor = page.pageInfo.hasNextPage ? page.pageInfo.endCursor : nil
        } while cursor != nil
        return collected
    }

    private func fetchPage(search: String, after: String?) async throws -> GQLSearch {
        var variables: [String: Any] = ["q": search, "first": Self.pageSize]
        if let after { variables["after"] = after }
        let data: GQLSearchData = try await Self.post(token: token, query: """
        query($q: String!, $first: Int!, $after: String) {
          search(query: $q, type: ISSUE, first: $first, after: $after) {
            issueCount
            pageInfo { hasNextPage endCursor }
            nodes { ...prFields }
          }
        }
        \(Self.fragment)
        """, variables: variables)
        return data.search
    }

    /// The account the token belongs to. Asked through the same endpoint as the
    /// queue, so a bad token or a rate limit fails in the same recognizable way.
    static func viewerLogin(token: String) async throws -> String {
        let data: GQLViewerData = try await post(token: token, query: "query { viewer { login } }", variables: [:])
        return data.viewer.login
    }

    private static func post<T: Decodable & Sendable>(
        token: String,
        query: String,
        variables: [String: Any]
    ) async throws -> T {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("PRQueue", forHTTPHeaderField: "User-Agent")

        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["query": query, "variables": variables]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw GitHubClientError.from(
                status: http.statusCode,
                headers: http.allHeaderFields,
                body: String(decoding: data, as: UTF8.self)
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(GQLEnvelope<T>.self, from: data)
        if let errors = envelope.errors, !errors.isEmpty {
            // GraphQL reports a spent point budget with HTTP 200.
            if errors.contains(where: { $0.type == "RATE_LIMITED" }) {
                throw GitHubClientError.rateLimited(resetAt: nil)
            }
            throw GitHubClientError.graphQL(errors.map(\.message))
        }
        guard let result = envelope.data else { throw GitHubClientError.emptyResponse }
        return result
    }
}

extension PullRequest {
    /// Flattens one GraphQL node. Returns nil for search results that are not
    /// pull requests, which decode as an empty object.
    init?(node: GQLPullRequest, viewer: String, isMine: Bool) {
        guard let number = node.number,
              let repo = node.repository?.nameWithOwner,
              let title = node.title,
              let url = node.url,
              let createdAt = node.createdAt,
              let updatedAt = node.updatedAt
        else { return nil }

        let reviewers = node.reviewRequests?.nodes?.compactMap(\.requestedReviewer) ?? []
        let myReviews = (node.reviews?.nodes ?? [])
            .filter { $0.author?.login == viewer && $0.state != "PENDING" }
            .sorted { ($0.submittedAt ?? .distantPast) < ($1.submittedAt ?? .distantPast) }
        let login = node.author?.login ?? "unknown"

        self.init(
            repo: repo,
            number: number,
            title: title,
            url: url,
            isDraft: node.isDraft ?? false,
            isPrivate: node.repository?.isPrivate ?? false,
            isArchived: node.repository?.isArchived ?? false,
            createdAt: createdAt,
            updatedAt: updatedAt,
            additions: node.additions ?? 0,
            deletions: node.deletions ?? 0,
            changedFiles: node.changedFiles ?? 0,
            reviewDecision: node.reviewDecision,
            authorLogin: login,
            authorIsBot: Self.looksLikeBot(login: login, typename: node.author?.__typename),
            requestedUsers: reviewers.filter { $0.__typename == "User" }.compactMap(\.login),
            requestedTeams: reviewers.filter { $0.__typename == "Team" }.compactMap(\.slug),
            myReviewState: myReviews.last?.state,
            myReviewAt: myReviews.last?.submittedAt,
            ciState: node.commits?.nodes?.first?.commit?.statusCheckRollup?.state ?? "NONE",
            lastCommitAt: node.commits?.nodes?.first?.commit?.committedDate,
            commentCount: node.comments?.totalCount ?? 0,
            reviewCount: node.reviews?.totalCount ?? 0,
            labels: node.labels?.nodes?.compactMap(\.name) ?? [],
            isMine: isMine
        )
    }

    /// GitHub marks some automation as a User, so the login is checked too.
    /// These names are the ones that actually appear in the queue.
    static func looksLikeBot(login: String, typename: String?) -> Bool {
        if typename == "Bot" { return true }
        let lower = login.lowercased()
        if lower.hasSuffix("[bot]") || lower.hasSuffix("-bot") || lower.hasSuffix("bot") { return true }
        return ["dependabot", "renovate", "sentry", "getsantry", "seer-by-sentry"].contains(lower)
    }
}
