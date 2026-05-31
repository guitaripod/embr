import Foundation

public enum RecentMessagesParser {
    public static func messages(fromLines lines: [String], channelID: String) -> [ChatMessage] {
        lines.compactMap { line in
            guard let parsed = IRCMessage.parse(line) else { return nil }
            switch parsed.command.uppercased() {
            case "PRIVMSG", "USERNOTICE":
                return IRCMapper.chatMessage(from: parsed, channelID: channelID)
            default:
                return nil
            }
        }
    }

    public static func messages(fromJSON data: Data, channelID: String) -> [ChatMessage] {
        guard let payload = try? JSONDecoder().decode(RecentMessagesPayload.self, from: data) else {
            return []
        }
        return messages(fromLines: payload.messages, channelID: channelID)
    }

    private struct RecentMessagesPayload: Decodable {
        let messages: [String]
    }
}
