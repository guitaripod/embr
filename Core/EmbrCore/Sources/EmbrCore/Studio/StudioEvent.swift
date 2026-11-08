import Foundation

/// Something that happened on the streamer's channel that Embr Studio shows: an alert for the feed, a moment that
/// takes over part of the screen, or a change of the channel's state. Chat itself goes through the chat engine; these
/// are everything around it.
public enum StudioEvent: Sendable, Equatable {
    case follow(StudioFollow)
    case subscription(StudioSubscription)
    case giftBomb(StudioGiftBomb)
    case cheer(StudioCheer)
    case powerUp(StudioPowerUp)
    case raid(StudioRaid)
    case redemption(StudioRedemption)
    case hypeTrain(StudioHypeTrain)
    case poll(StudioPoll)
    case prediction(StudioPrediction)
    case goal(StudioGoal)
    case adBreakBegan(StudioAdBreak)
    case streamOnline(startedAt: Date)
    case streamOffline
    case channelUpdated(title: String, categoryName: String)
    case sharedChat(StudioSharedChat?)
    case shieldMode(active: Bool)
    case charity(StudioCharityDonation)

    /// The person an alert is about, for showing their card or acting on them.
    public var userID: String? {
        switch self {
        case .follow(let value): value.userID
        case .subscription(let value): value.userID
        case .giftBomb(let value): value.gifterID
        case .cheer(let value): value.userID
        case .powerUp(let value): value.userID
        case .raid(let value): value.raiderID
        case .redemption(let value): value.userID
        case .charity(let value): value.userID
        default: nil
        }
    }
}

/// The subscription tier as Twitch names it: 1000, 2000 or 3000.
public enum StudioTier: String, Sendable, Equatable, Codable {
    case one = "1000"
    case two = "2000"
    case three = "3000"

    public var number: Int {
        switch self {
        case .one: 1
        case .two: 2
        case .three: 3
        }
    }
}

public struct StudioFollow: Sendable, Equatable {
    public let userID: String
    public let userName: String
    public let followedAt: Date

    public init(userID: String, userName: String, followedAt: Date) {
        self.userID = userID
        self.userName = userName
        self.followedAt = followedAt
    }
}

public struct StudioSubscription: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// A first subscription.
        case new
        /// A resubscription with the months shared in chat.
        case resub(months: Int)
        /// One gifted subscription, outside a gift bomb.
        case gift(recipientName: String)
        /// A gifted subscription continued with the person's own money.
        case giftUpgrade
        /// A Prime subscription continued with the person's own money.
        case primeUpgrade
        /// A gifted subscriber gifting one onward.
        case payItForward
    }

    public let id: String
    public let userID: String
    public let userName: String
    public let kind: Kind
    public let tier: StudioTier
    public let isPrime: Bool
    public let message: String

    public init(id: String, userID: String, userName: String, kind: Kind, tier: StudioTier, isPrime: Bool, message: String) {
        self.id = id
        self.userID = userID
        self.userName = userName
        self.kind = kind
        self.tier = tier
        self.isPrime = isPrime
        self.message = message
    }
}

/// A gift bomb: someone gifting several subscriptions at once, shown as one alert however many gifts follow it.
public struct StudioGiftBomb: Sendable, Equatable {
    public let id: String
    public let gifterID: String?
    public let gifterName: String?
    public let count: Int
    public let tier: StudioTier

    public init(id: String, gifterID: String?, gifterName: String?, count: Int, tier: StudioTier) {
        self.id = id
        self.gifterID = gifterID
        self.gifterName = gifterName
        self.count = count
        self.tier = tier
    }
}

public struct StudioCheer: Sendable, Equatable {
    public let id: String
    public let userID: String?
    public let userName: String?
    public let bits: Int
    public let message: String

    public init(id: String, userID: String?, userName: String?, bits: Int, message: String) {
        self.id = id
        self.userID = userID
        self.userName = userName
        self.bits = bits
        self.message = message
    }
}

public struct StudioPowerUp: Sendable, Equatable {
    public let userID: String
    public let userName: String
    public let bits: Int
    /// The Power-up's own name: a custom Power-up's title, or the built-in kind.
    public let title: String

    public init(userID: String, userName: String, bits: Int, title: String) {
        self.userID = userID
        self.userName = userName
        self.bits = bits
        self.title = title
    }
}

public struct StudioRaid: Sendable, Equatable {
    public let raiderID: String
    public let raiderName: String
    public let raiderLogin: String
    public let viewers: Int
    public let profileImageURL: URL?

    public init(raiderID: String, raiderName: String, raiderLogin: String, viewers: Int, profileImageURL: URL?) {
        self.raiderID = raiderID
        self.raiderName = raiderName
        self.raiderLogin = raiderLogin
        self.viewers = viewers
        self.profileImageURL = profileImageURL
    }
}

public struct StudioRedemption: Sendable, Equatable {
    public let id: String
    public let userID: String
    public let userName: String
    public let rewardTitle: String
    public let cost: Int
    public let input: String

    public init(id: String, userID: String, userName: String, rewardTitle: String, cost: Int, input: String) {
        self.id = id
        self.userID = userID
        self.userName = userName
        self.rewardTitle = rewardTitle
        self.cost = cost
        self.input = input
    }
}

public struct StudioContributor: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case bits
        case subscription
        case other
    }

    public let userName: String
    public let kind: Kind
    public let total: Int

    public init(userName: String, kind: Kind, total: Int) {
        self.userName = userName
        self.kind = kind
        self.total = total
    }
}

public struct StudioHypeTrain: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case running
        case ended
    }

    public let id: String
    public let phase: Phase
    public let level: Int
    public let progress: Int
    public let goal: Int
    public let total: Int
    public let expiresAt: Date?
    public let topContributors: [StudioContributor]
    public let isGolden: Bool

    public init(id: String, phase: Phase, level: Int, progress: Int, goal: Int, total: Int, expiresAt: Date?, topContributors: [StudioContributor], isGolden: Bool) {
        self.id = id
        self.phase = phase
        self.level = level
        self.progress = progress
        self.goal = goal
        self.total = total
        self.expiresAt = expiresAt
        self.topContributors = topContributors
        self.isGolden = isGolden
    }

    /// How far the train is toward its next level, 0 to 1.
    public var fraction: Double {
        guard goal > 0 else { return 0 }
        return min(max(Double(progress) / Double(goal), 0), 1)
    }
}

public struct StudioChoice: Sendable, Equatable {
    public let id: String
    public let title: String
    public let votes: Int

    public init(id: String, title: String, votes: Int) {
        self.id = id
        self.title = title
        self.votes = votes
    }
}

public struct StudioPoll: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case open
        case ended
    }

    public let id: String
    public let title: String
    public let choices: [StudioChoice]
    public let endsAt: Date?
    public let phase: Phase

    public init(id: String, title: String, choices: [StudioChoice], endsAt: Date?, phase: Phase) {
        self.id = id
        self.title = title
        self.choices = choices
        self.endsAt = endsAt
        self.phase = phase
    }

    public var totalVotes: Int { choices.reduce(0) { $0 + $1.votes } }

    /// The leading choice once the poll has ended, nil on a tie or no votes.
    public var winner: StudioChoice? {
        guard let top = choices.max(by: { $0.votes < $1.votes }), top.votes > 0 else { return nil }
        return choices.filter { $0.votes == top.votes }.count == 1 ? top : nil
    }
}

public struct StudioPrediction: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case open
        case locked
        case resolved(winningOutcomeID: String?)
        case canceled
    }

    public let id: String
    public let title: String
    public let outcomes: [StudioChoice]
    public let locksAt: Date?
    public let phase: Phase

    public init(id: String, title: String, outcomes: [StudioChoice], locksAt: Date?, phase: Phase) {
        self.id = id
        self.title = title
        self.outcomes = outcomes
        self.locksAt = locksAt
        self.phase = phase
    }

    /// Channel points on each outcome, as Twitch reports them (`channel_points` per outcome).
    public var totalPoints: Int { outcomes.reduce(0) { $0 + $1.votes } }
}

public struct StudioGoal: Sendable, Equatable {
    public let id: String
    public let kind: String
    public let description: String
    public let current: Int
    public let target: Int
    public let ended: Bool
    public let achieved: Bool

    public init(id: String, kind: String, description: String, current: Int, target: Int, ended: Bool, achieved: Bool) {
        self.id = id
        self.kind = kind
        self.description = description
        self.current = current
        self.target = target
        self.ended = ended
        self.achieved = achieved
    }

    public var fraction: Double {
        guard target > 0 else { return 0 }
        return min(max(Double(current) / Double(target), 0), 1)
    }
}

public struct StudioAdBreak: Sendable, Equatable {
    public let startedAt: Date
    public let duration: TimeInterval
    public let isAutomatic: Bool

    public init(startedAt: Date, duration: TimeInterval, isAutomatic: Bool) {
        self.startedAt = startedAt
        self.duration = duration
        self.isAutomatic = isAutomatic
    }

    public var endsAt: Date { startedAt.addingTimeInterval(duration) }
}

public struct StudioSharedChat: Sendable, Equatable {
    public let sessionID: String
    /// The other channels in the session, by display name.
    public let participants: [String]

    public init(sessionID: String, participants: [String]) {
        self.sessionID = sessionID
        self.participants = participants
    }
}

public struct StudioCharityDonation: Sendable, Equatable {
    public let userID: String
    public let userName: String
    public let charityName: String
    /// The amount in the currency's minor unit, as Twitch sends it.
    public let minorUnits: Int
    public let decimalPlaces: Int
    public let currency: String

    public init(userID: String, userName: String, charityName: String, minorUnits: Int, decimalPlaces: Int, currency: String) {
        self.userID = userID
        self.userName = userName
        self.charityName = charityName
        self.minorUnits = minorUnits
        self.decimalPlaces = decimalPlaces
        self.currency = currency
    }

    public var amount: Decimal {
        var value = Decimal(minorUnits)
        for _ in 0..<max(decimalPlaces, 0) { value /= 10 }
        return value
    }
}
