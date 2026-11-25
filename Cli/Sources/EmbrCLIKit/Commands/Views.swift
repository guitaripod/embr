import Foundation
import EmbrCore

struct ChannelUserView: Encodable {
    let userID: String
    let userLogin: String
    let userName: String

    init(_ user: ChannelUser) {
        userID = user.userID
        userLogin = user.userLogin
        userName = user.userName
    }
}

struct BannedUserView: Encodable {
    let userID: String
    let userLogin: String
    let userName: String
    let permanent: Bool
    let createdAt: Date
    let expiresAt: Date?
    let reason: String?
    let moderatorID: String
    let moderatorLogin: String
    let moderatorName: String

    init(_ user: BannedUser) {
        userID = user.userID
        userLogin = user.userLogin
        userName = user.userName
        permanent = user.isPermanent
        createdAt = user.createdAt
        expiresAt = user.expiresAt
        reason = user.reason
        moderatorID = user.moderatorID
        moderatorLogin = user.moderatorLogin
        moderatorName = user.moderatorName
    }
}
