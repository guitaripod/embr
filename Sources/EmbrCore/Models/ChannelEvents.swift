import Foundation

public struct ChannelEvents: Sendable, Equatable, Codable {
    public let poll: LivePoll?
    public let prediction: LivePrediction?

    public init(poll: LivePoll? = nil, prediction: LivePrediction? = nil) {
        self.poll = poll
        self.prediction = prediction
    }

    public static let empty = ChannelEvents(poll: nil, prediction: nil)
}

public struct LivePoll: Sendable, Equatable, Codable, Identifiable {
    public struct Choice: Sendable, Equatable, Codable {
        public let title: String
        public let votes: Int

        public init(title: String, votes: Int) {
            self.title = title
            self.votes = votes
        }
    }

    public let id: String
    public let title: String
    public let status: String
    public let endsAt: Double
    public let totalVotes: Int
    public let choices: [Choice]

    public init(id: String, title: String, status: String, endsAt: Double, totalVotes: Int, choices: [Choice]) {
        self.id = id
        self.title = title
        self.status = status
        self.endsAt = endsAt
        self.totalVotes = totalVotes
        self.choices = choices
    }

    public var endsAtDate: Date { Date(timeIntervalSince1970: endsAt) }
}

public struct LivePrediction: Sendable, Equatable, Codable, Identifiable {
    public struct Outcome: Sendable, Equatable, Codable {
        public let title: String
        public let color: String
        public let points: Int
        public let users: Int

        public init(title: String, color: String, points: Int, users: Int) {
            self.title = title
            self.color = color
            self.points = points
            self.users = users
        }
    }

    public let id: String
    public let title: String
    public let status: String
    public let locksAt: Double
    public let outcomes: [Outcome]

    public init(id: String, title: String, status: String, locksAt: Double, outcomes: [Outcome]) {
        self.id = id
        self.title = title
        self.status = status
        self.locksAt = locksAt
        self.outcomes = outcomes
    }

    public var locksAtDate: Date { Date(timeIntervalSince1970: locksAt) }
    public var isLocked: Bool { status == "LOCKED" }
    public var totalPoints: Int { outcomes.reduce(0) { $0 + $1.points } }
}
