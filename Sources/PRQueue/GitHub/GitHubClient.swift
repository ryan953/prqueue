import Foundation

enum GitHubClientError: LocalizedError {
    case http(Int, String)
    case graphQL([String])
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            "GitHub returned HTTP \(code): \(body.prefix(240))"
        case .graphQL(let messages):
            "GitHub GraphQL error: \(messages.joined(separator: "; "))"
        case .emptyResponse:
            "GitHub returned no data."
        }
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
        let query = """
        query($q: String!, $first: Int!, $after: String) {
          search(query: $q, type: ISSUE, first: $first, after: $after) {
            issueCount
            pageInfo { hasNextPage endCursor }
            nodes { ...prFields }
          }
        }
        \(Self.fragment)
        """

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("PRQueue", forHTTPHeaderField: "User-Agent")

        var variables: [String: Any] = ["q": search, "first": Self.pageSize]
        if let after { variables["after"] = after }
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["query": query, "variables": variables]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw GitHubClientError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(GQLEnvelope<GQLSearchData>.self, from: data)
        if let errors = envelope.errors, !errors.isEmpty {
            throw GitHubClientError.graphQL(errors.map(\.message))
        }
        guard let search = envelope.data?.search else { throw GitHubClientError.emptyResponse }
        return search
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
