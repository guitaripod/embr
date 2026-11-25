import Foundation

/// Reads the Helix responses Embr's models describe, so callers outside the app do not have to re-declare Twitch's JSON
/// shapes. Every page keeps Twitch's cursor; pages that report a total keep it too.
public enum HelixDecoder {
    public static func streams(_ data: Data) throws -> HelixResponse<LiveStream> {
        try page(data, transform: HelixMappers.liveStream)
    }

    public static func games(_ data: Data) throws -> HelixResponse<GameCategory> {
        try page(data, transform: HelixMappers.gameCategory)
    }

    public static func channelSearch(_ data: Data) throws -> HelixResponse<ChannelInfo> {
        try page(data, transform: { (dto: ChannelSearchDTO) in HelixMappers.channelInfo(dto) })
    }

    public static func users(_ data: Data) throws -> HelixResponse<TwitchUser> {
        try page(data, transform: HelixMappers.user)
    }

    public static func channelInfo(_ data: Data) throws -> HelixResponse<ChannelInfo> {
        try page(data, transform: { (dto: ChannelDTO) in HelixMappers.channelInfo(dto) })
    }

    public static func videos(_ data: Data) throws -> HelixResponse<VideoOnDemand> {
        try page(data, transform: HelixMappers.video)
    }

    public static func clips(_ data: Data) throws -> HelixResponse<Clip> {
        try page(data, transform: HelixMappers.clip)
    }

    public static func followedChannels(_ data: Data) throws -> HelixResponse<FollowedChannel> {
        try page(data, transform: HelixMappers.followedChannel)
    }

    public static func emotes(_ data: Data) throws -> HelixResponse<Emote> {
        try page(data, transform: HelixMappers.emote)
    }

    public static func badges(_ data: Data) throws -> HelixResponse<Badge> {
        let page = try TwitchJSON.decode(HelixResponse<BadgeSetDTO>.self, from: data)
        return HelixResponse(
            data: HelixMappers.badges(page.data),
            pagination: page.pagination.map { .init(cursor: $0.cursor) },
            total: page.total
        )
    }

    public static func chatSettings(_ data: Data) throws -> RoomState? {
        let page = try TwitchJSON.decode(HelixResponse<ChatSettingsDTO>.self, from: data)
        return page.data.first.map(HelixMappers.roomState)
    }

    public static func sendResult(_ data: Data) throws -> SendResult? {
        let page = try TwitchJSON.decode(HelixResponse<SendMessageResultDTO>.self, from: data)
        return page.data.first.map(HelixMappers.sendResult)
    }

    public static func schedule(_ data: Data) throws -> SchedulePage {
        let page = try TwitchJSON.decode(ScheduleResponse.self, from: data)
        return SchedulePage(
            segments: try page.data.segments.map { segment in
                guard let start = TwitchJSON.date(from: segment.startTime) else {
                    throw APIError.decoding("Invalid schedule start_time: \(segment.startTime)")
                }
                return ScheduleSegment(
                    id: segment.id,
                    startTime: start,
                    endTime: segment.endTime.flatMap(TwitchJSON.date(from:)),
                    title: segment.title,
                    categoryName: segment.category?.name,
                    isRecurring: segment.isRecurring ?? false,
                    canceledUntil: segment.canceledUntil.flatMap(TwitchJSON.date(from:))
                )
            },
            broadcasterID: page.data.broadcasterID,
            broadcasterName: page.data.broadcasterName,
            broadcasterLogin: page.data.broadcasterLogin,
            vacation: page.data.vacation.flatMap { vacation in
                guard let start = TwitchJSON.date(from: vacation.startTime),
                      let end = TwitchJSON.date(from: vacation.endTime) else { return nil }
                return DateInterval(start: start, end: end)
            },
            cursor: page.pagination?.cursor
        )
    }

    private static func page<DTO: Decodable & Sendable, Model: Sendable>(
        _ data: Data,
        transform: (DTO) -> Model
    ) throws -> HelixResponse<Model> {
        let page = try TwitchJSON.decode(HelixResponse<DTO>.self, from: data)
        return HelixResponse(
            data: page.data.map(transform),
            pagination: page.pagination.map { .init(cursor: $0.cursor) },
            total: page.total
        )
    }
}

/// One broadcaster's schedule. Twitch nests the segments in an object instead of the usual data array, so this page
/// has its own shape.
public struct SchedulePage: Sendable, Equatable {
    public let segments: [ScheduleSegment]
    public let broadcasterID: String?
    public let broadcasterName: String?
    public let broadcasterLogin: String?
    public let vacation: DateInterval?
    public let cursor: String?

    public init(
        segments: [ScheduleSegment],
        broadcasterID: String? = nil,
        broadcasterName: String? = nil,
        broadcasterLogin: String? = nil,
        vacation: DateInterval? = nil,
        cursor: String? = nil
    ) {
        self.segments = segments
        self.broadcasterID = broadcasterID
        self.broadcasterName = broadcasterName
        self.broadcasterLogin = broadcasterLogin
        self.vacation = vacation
        self.cursor = cursor
    }
}

struct ScheduleResponse: Decodable, Sendable {
    let data: ScheduleDTO
    let pagination: HelixResponse<ScheduleSegmentDTO>.Pagination?
}

struct ScheduleDTO: Decodable, Sendable {
    let segments: [ScheduleSegmentDTO]
    let broadcasterID: String?
    let broadcasterName: String?
    let broadcasterLogin: String?
    let vacation: VacationDTO?

    enum CodingKeys: String, CodingKey {
        case segments
        case broadcasterID = "broadcaster_id"
        case broadcasterName = "broadcaster_name"
        case broadcasterLogin = "broadcaster_login"
        case vacation
    }
}

struct ScheduleSegmentDTO: Decodable, Sendable {
    let id: String
    let startTime: String
    let endTime: String?
    let title: String
    let canceledUntil: String?
    let category: CategoryDTO?
    let isRecurring: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case startTime = "start_time"
        case endTime = "end_time"
        case title
        case canceledUntil = "canceled_until"
        case category
        case isRecurring = "is_recurring"
    }

    struct CategoryDTO: Decodable, Sendable {
        let id: String
        let name: String
    }
}

struct VacationDTO: Decodable, Sendable {
    let startTime: String
    let endTime: String

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
    }
}
