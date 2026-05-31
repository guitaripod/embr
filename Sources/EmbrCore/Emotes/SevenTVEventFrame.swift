import Foundation

public enum SevenTVEvent: Sendable, Equatable {
    case hello(heartbeatMS: Int, sessionID: String)
    case dispatch(EmoteSetUpdate)
    case heartbeat
    case other
}

public enum SevenTVEventFrame {
    static let opDispatch = 0
    static let opHello = 1
    static let opHeartbeat = 2
    static let opSubscribe = 35

    struct Frame: Decodable {
        let op: Int
        let d: Dispatch?
    }

    struct Dispatch: Decodable {
        let heartbeat_interval: Int?
        let session_id: String?
        let type: String?
        let body: Body?
    }

    struct Body: Decodable {
        let id: String?
        let actor: Actor?
        let pushed: [ChangeField]?
        let pulled: [ChangeField]?
    }

    struct Actor: Decodable {
        let display_name: String?
    }

    struct ChangeField: Decodable {
        let key: String?
        let index: Int?
        let value: SevenTVDTO.EmoteEntry?
        let old_value: OldValue?
    }

    struct OldValue: Decodable {
        let id: String?
        let name: String?
    }

    public static func decode(_ data: Data) throws -> SevenTVEvent {
        let frame = try TwitchJSON.decode(Frame.self, from: data)
        switch frame.op {
        case opHello:
            guard let interval = frame.d?.heartbeat_interval, let session = frame.d?.session_id else {
                return .other
            }
            return .hello(heartbeatMS: interval, sessionID: session)
        case opHeartbeat:
            return .heartbeat
        case opDispatch:
            guard let dispatch = frame.d, dispatch.type == "emote_set.update", let body = dispatch.body else {
                return .other
            }
            return .dispatch(update(from: body))
        default:
            return .other
        }
    }

    public static func subscribeFrame(emoteSetID: String) throws -> Data {
        let payload: [String: Any] = [
            "op": opSubscribe,
            "d": [
                "type": "emote_set.update",
                "condition": ["object_id": emoteSetID]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    static func update(from body: Body) -> EmoteSetUpdate {
        let added = (body.pushed ?? []).compactMap { $0.value }.compactMap(mapEntry)
        let removed = (body.pulled ?? []).compactMap { $0.old_value?.name }
        return EmoteSetUpdate(added: added, removed: removed, actor: body.actor?.display_name)
    }

    private static func mapEntry(_ entry: SevenTVDTO.EmoteEntry) -> Emote? {
        if let mapped = SevenTVDTO.map([entry]).first { return mapped }
        let flags = entry.flags ?? 0
        return Emote(
            id: entry.id,
            name: entry.name,
            provider: .sevenTV,
            images: EmoteImageSet(urlsByScale: [:]),
            isAnimated: entry.data?.animated ?? false,
            isZeroWidth: (flags & SevenTVDTO.zeroWidthFlag) != 0,
            aspectRatio: 1.0,
            ownerID: nil
        )
    }
}
