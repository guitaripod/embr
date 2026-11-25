import Foundation
import EmbrCore

enum StudioCommands {
    static let specs: [CommandSpec] = [
        adSchedule,
        adStart,
        adSnooze,
        hypeTrain,
        poll,
        prediction,
        goals,
        followers,
        shieldStatus,
        shieldOn,
        shieldOff
    ]

    static let adSchedule = CommandSpec(
        ["studio", "ad-schedule"],
        summary: "The channel's ad schedule and snooze budget.",
        positionals: [PositionalSpec("channel", "Channel login or id.")],
        examples: ["embr studio ad-schedule xqc"],
        scopes: ["channel:read:ads"]
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.adSchedule(broadcasterID: broadcaster.id, token: token)
        if let raw = try await CommandSupport.raw(request, context) { return raw }
        let response = try await context.send(request)
        guard let schedule = StudioHelixDecoder.adSchedule(response.body, fetchedAt: Date()) else {
            throw CLIError.notFound("Twitch returned no ad schedule for \(broadcaster.login).")
        }
        return CommandResult(AdScheduleView(channel: broadcaster.login, schedule: schedule), count: 1)
    }

    static let adStart = CommandSpec(
        ["studio", "ad-start"],
        summary: "Start a commercial break.",
        positionals: [PositionalSpec("channel", "Channel login or id.")],
        options: [.value("length", "SECONDS", "Commercial length.", required: true, range: 30...180)],
        examples: ["embr studio ad-start xqc --length 60"],
        scopes: ["channel:edit:commercial"],
        mutating: true
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let length = invocation.int("length") ?? 60
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.startCommercial(broadcasterID: broadcaster.id, length: length, token: token)
        let response = try await context.send(request)
        guard let result = StudioHelixDecoder.commercial(response.body) else {
            throw CLIError(.decode, "Twitch returned no commercial result.")
        }
        return CommandResult(CommercialView(channel: broadcaster.login, result: result), count: 1)
    }

    static let adSnooze = CommandSpec(
        ["studio", "ad-snooze"],
        summary: "Snooze the next automatic mid-roll ad.",
        positionals: [PositionalSpec("channel", "Channel login or id.")],
        examples: ["embr studio ad-snooze xqc"],
        scopes: ["channel:manage:ads"],
        mutating: true
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.snoozeNextAd(broadcasterID: broadcaster.id, token: token)
        let response = try await context.send(request)
        let schedule = StudioHelixDecoder.snoozed(response.body, previous: nil, fetchedAt: Date())
        return CommandResult(SnoozeView(channel: broadcaster.login, schedule: schedule), count: 1)
    }

    static let hypeTrain = CommandSpec(
        ["studio", "hype-train"],
        summary: "The channel's current Hype Train.",
        positionals: [PositionalSpec("channel", "Channel login or id.")],
        examples: ["embr studio hype-train xqc --json"],
        scopes: ["channel:read:hype_train"]
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.hypeTrainStatus(broadcasterID: broadcaster.id, token: token)
        let response = try await context.send(request)
        let train = StudioHelixDecoder.hypeTrain(response.body)
        return CommandResult(HypeTrainView(channel: broadcaster.login, active: train != nil, train: train.map(HypeTrainDetail.init)), count: train == nil ? 0 : 1)
    }

    static let poll = CommandSpec(
        ["studio", "poll"],
        summary: "The channel's active poll.",
        positionals: [PositionalSpec("channel", "Channel login or id.")],
        examples: ["embr studio poll xqc --json"],
        scopes: ["channel:read:polls"]
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.polls(broadcasterID: broadcaster.id, token: token)
        let response = try await context.send(request)
        let active = StudioHelixDecoder.activePoll(response.body)
        return CommandResult(PollView(channel: broadcaster.login, active: active != nil, poll: active.map(PollDetail.init)), count: active == nil ? 0 : 1)
    }

    static let prediction = CommandSpec(
        ["studio", "prediction"],
        summary: "The channel's active or locked prediction.",
        positionals: [PositionalSpec("channel", "Channel login or id.")],
        examples: ["embr studio prediction xqc --json"],
        scopes: ["channel:read:predictions"]
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.predictions(broadcasterID: broadcaster.id, token: token)
        let response = try await context.send(request)
        let active = StudioHelixDecoder.activePrediction(response.body)
        return CommandResult(PredictionView(channel: broadcaster.login, active: active != nil, prediction: active.map(PredictionDetail.init)), count: active == nil ? 0 : 1)
    }

    static let goals = CommandSpec(
        ["studio", "goals"],
        summary: "The channel's creator goals.",
        positionals: [PositionalSpec("channel", "Channel login or id.")],
        examples: ["embr studio goals xqc --json"],
        scopes: ["channel:read:goals"]
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.creatorGoals(broadcasterID: broadcaster.id, token: token)
        let response = try await context.send(request)
        let goals = StudioHelixDecoder.goals(response.body)
        let table = CommandSupport.table(
            ["KIND", "DESCRIPTION", "CURRENT", "TARGET", "ENDED"],
            goals.map { [$0.kind, $0.description, String($0.current), String($0.target), CommandSupport.yesNo($0.ended)] }
        )
        return CommandSupport.list(goals, table: table, cursor: nil)
    }

    static let followers = CommandSpec(
        ["studio", "followers"],
        summary: "Follower total and the newest followers.",
        positionals: [PositionalSpec("channel", "Channel login or id.")],
        examples: ["embr studio followers xqc --first 20"],
        scopes: ["moderator:read:followers"]
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let factory = try context.factory()
        let token = try context.token()
        let first = invocation.int("first") ?? context.options.first ?? 20
        let request = factory.channelFollowers(broadcasterID: broadcaster.id, first: first, token: token)
        let response = try await context.send(request)
        let decoded = StudioHelixDecoder.followers(response.body)
        let table = CommandSupport.table(
            ["USER", "ID", "FOLLOWED"],
            decoded.recent.map { [$0.userName, $0.userID, CommandSupport.timestamp($0.followedAt)] }
        )
        return CommandResult(
            ChannelFollowersView(total: decoded.total, followers: decoded.recent),
            items: decoded.recent.map { AnyEncodable($0) },
            table: table,
            total: decoded.total,
            count: decoded.recent.count
        )
    }

    static let shieldStatus = CommandSpec(
        ["studio", "shield", "status"],
        summary: "Whether Shield Mode is active.",
        positionals: [PositionalSpec("channel", "Channel login or id.")],
        options: [.value("as", "USER", "Moderator identity (default: you).")],
        examples: ["embr studio shield status xqc"],
        scopes: ["moderator:read:shield_mode"]
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let moderatorID = try await context.moderatorID(invocation.value("as"))
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.shieldModeStatus(broadcasterID: broadcaster.id, moderatorID: moderatorID, token: token)
        let response = try await context.send(request)
        let active = StudioHelixDecoder.shieldModeActive(response.body) ?? false
        return CommandResult(ShieldView(channel: broadcaster.login, active: active), count: 1)
    }

    static let shieldOn = shield(active: true, path: ["studio", "shield", "on"], summary: "Turn Shield Mode on.")
    static let shieldOff = shield(active: false, path: ["studio", "shield", "off"], summary: "Turn Shield Mode off.")

    private static func shield(active: Bool, path: [String], summary: String) -> CommandSpec {
        CommandSpec(
            path,
            summary: summary,
            positionals: [PositionalSpec("channel", "Channel login or id.")],
            options: [.value("as", "USER", "Moderator identity (default: you).")],
            examples: ["embr \(path.joined(separator: " ")) xqc"],
            scopes: ["moderator:manage:shield_mode"],
            mutating: true
        ) { invocation, context in
            let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
            let moderatorID = try await context.moderatorID(invocation.value("as"))
            let factory = try context.factory()
            let token = try context.token()
            let request = factory.shieldMode(broadcasterID: broadcaster.id, moderatorID: moderatorID, active: active, token: token)
            let response = try await context.send(request)
            guard response.status == 204 || response.status == 200 else {
                throw CLIError.http(status: response.status, body: response.body)
            }
            return CommandResult(ShieldView(channel: broadcaster.login, active: active))
        }
    }
}

private struct AdScheduleView: Encodable {
    let channel: String
    let schedule: AdSchedule
}

private struct CommercialView: Encodable {
    let channel: String
    let result: CommercialResult
}

private struct SnoozeView: Encodable {
    let channel: String
    let schedule: AdSchedule?
}

private struct HypeTrainView: Encodable {
    let channel: String
    let active: Bool
    let train: HypeTrainDetail?
}

private struct HypeTrainDetail: Encodable {
    let id: String
    let phase: String
    let level: Int
    let progress: Int
    let goal: Int
    let total: Int
    let expiresAt: Date?
    let golden: Bool
    let contributors: [ContributorView]

    init(_ train: StudioHypeTrain) {
        id = train.id
        phase = train.phase == .running ? "running" : "ended"
        level = train.level
        progress = train.progress
        goal = train.goal
        total = train.total
        expiresAt = train.expiresAt
        golden = train.isGolden
        contributors = train.topContributors.map(ContributorView.init)
    }
}

private struct ContributorView: Encodable {
    let name: String
    let kind: String
    let total: Int

    init(_ contributor: StudioContributor) {
        name = contributor.userName
        kind = contributor.kind.rawValue
        total = contributor.total
    }
}

private struct PollView: Encodable {
    let channel: String
    let active: Bool
    let poll: PollDetail?
}

private struct PollDetail: Encodable {
    let id: String
    let title: String
    let phase: String
    let endsAt: Date?
    let totalVotes: Int
    let choices: [ChoiceView]

    init(_ poll: StudioPoll) {
        id = poll.id
        title = poll.title
        phase = poll.phase == .open ? "open" : "ended"
        endsAt = poll.endsAt
        totalVotes = poll.totalVotes
        choices = poll.choices.map(ChoiceView.init)
    }
}

private struct ChoiceView: Encodable {
    let id: String
    let title: String
    let votes: Int

    init(_ choice: StudioChoice) {
        id = choice.id
        title = choice.title
        votes = choice.votes
    }
}

private struct PredictionView: Encodable {
    let channel: String
    let active: Bool
    let prediction: PredictionDetail?
}

private struct PredictionDetail: Encodable {
    let id: String
    let title: String
    let phase: String
    let locksAt: Date?
    let totalPoints: Int
    let outcomes: [ChoiceView]

    init(_ prediction: StudioPrediction) {
        id = prediction.id
        title = prediction.title
        switch prediction.phase {
        case .open: phase = "open"
        case .locked: phase = "locked"
        case .resolved(let winning): phase = winning.map { "resolved:\($0)" } ?? "resolved"
        case .canceled: phase = "canceled"
        }
        locksAt = prediction.locksAt
        totalPoints = prediction.totalPoints
        outcomes = prediction.outcomes.map(ChoiceView.init)
    }
}

private struct ChannelFollowersView: Encodable {
    let total: Int
    let followers: [StudioFollow]
}

private struct ShieldView: Encodable {
    let channel: String
    let active: Bool
}
