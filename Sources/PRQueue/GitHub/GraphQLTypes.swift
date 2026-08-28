import Foundation

// Decoding shapes for the GitHub GraphQL search response. Every PR field is
// optional because a search of type ISSUE also returns plain issues, which
// match none of the pull request fragment.

struct GQLEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
    let data: T?
    let errors: [GQLError]?
}

struct GQLError: Decodable, Sendable {
    let message: String
}

struct GQLSearchData: Decodable, Sendable {
    let search: GQLSearch
}

struct GQLSearch: Decodable, Sendable {
    let issueCount: Int
    let pageInfo: GQLPageInfo
    let nodes: [GQLPullRequest]
}

struct GQLPageInfo: Decodable, Sendable {
    let hasNextPage: Bool
    let endCursor: String?
}

struct GQLPullRequest: Decodable, Sendable {
    let number: Int?
    let title: String?
    let url: String?
    let isDraft: Bool?
    let createdAt: Date?
    let updatedAt: Date?
    let additions: Int?
    let deletions: Int?
    let changedFiles: Int?
    let reviewDecision: String?
    let author: GQLActor?
    let repository: GQLRepository?
    let reviewRequests: GQLReviewRequests?
    let reviews: GQLReviews?
    let comments: GQLComments?
    let commits: GQLCommits?
    let labels: GQLLabels?
}

struct GQLActor: Decodable, Sendable {
    let login: String?
    let __typename: String?
}

struct GQLRepository: Decodable, Sendable {
    let nameWithOwner: String?
    let isPrivate: Bool?
    let isArchived: Bool?
}

struct GQLReviewRequests: Decodable, Sendable {
    let nodes: [GQLReviewRequest]?
}

struct GQLReviewRequest: Decodable, Sendable {
    let requestedReviewer: GQLReviewer?
}

struct GQLReviewer: Decodable, Sendable {
    let __typename: String?
    let login: String?
    let slug: String?
}

struct GQLReviews: Decodable, Sendable {
    let totalCount: Int?
    let nodes: [GQLReview]?
}

struct GQLComments: Decodable, Sendable {
    let totalCount: Int?
}

struct GQLReview: Decodable, Sendable {
    let author: GQLActor?
    let state: String?
    let submittedAt: Date?
}

struct GQLCommits: Decodable, Sendable {
    let nodes: [GQLCommitNode]?
}

struct GQLCommitNode: Decodable, Sendable {
    let commit: GQLCommit?
}

struct GQLCommit: Decodable, Sendable {
    let committedDate: Date?
    let statusCheckRollup: GQLRollup?
}

struct GQLRollup: Decodable, Sendable {
    let state: String?
}

struct GQLLabels: Decodable, Sendable {
    let nodes: [GQLLabel]?
}

struct GQLLabel: Decodable, Sendable {
    let name: String?
}
