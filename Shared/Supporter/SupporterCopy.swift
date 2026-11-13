import Foundation

/// What Founding Member is called and what its screens say, in one place for iPhone, iPad and Apple TV. The product
/// id, the entitlement, the worker routes and the types keep the name `supporter`; these are the only words people
/// read, and each of them says what the buyer gets.
enum SupporterCopy {
    /// The status as people read it: "Founding Member #12", or without a number until the badge is claimed.
    static func name(number: Int?) -> String {
        number.map { String(localized: "Founding Member #\($0)") } ?? String(localized: "Founding Member")
    }

    static var invitation: String { String(localized: "Make Embr Yours") }

    /// What the purchase holds, for someone who has not bought it. The Apple TV has no app icons to try on.
    static var invitationBody: String {
        #if os(tvOS)
        String(localized: "Themes, accent colors, chat fonts and a flame badge everyone in Embr sees beside your name, with a founding number that stays yours. Try them on below; Studio never needs any of it.")
        #else
        String(localized: "Themes, accent colors, chat fonts, app icons and a flame badge everyone in Embr sees beside your name, with a founding number that stays yours. Try them on below; watching never needs any of it.")
        #endif
    }

    static var ownerBody: String { String(localized: "Everything here is yours to change any time.") }

    /// What a new owner hears once the purchase lands.
    static func bought(number: Int?) -> String {
        number.map { String(localized: "You're Founding Member #\($0). Every look is yours.") }
            ?? String(localized: "You're a Founding Member. Every look is yours.")
    }

    /// The line under the buy button: how many people are in, once there are enough to say so.
    static func purchaseNote(count: Int) -> String {
        guard count >= 10 else {
            return String(localized: "One purchase, yours on every device with your Apple Account. Founding numbers go in order and stay yours.")
        }
        return String(localized: "Join \(count) Founding Members. One purchase, yours on every device with your Apple Account.")
    }

    static var nothingToRestore: String { String(localized: "This Apple Account hasn't bought Founding Member yet.") }
}
