import EmbrCore
import Foundation
import Testing
import UIKit

@testable import Embr

private struct UnusedTransport: HTTPTransport {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        throw URLError(.notConnectedToInternet)
    }
}

private func freshDefaults() -> UserDefaults {
    let name = "SupporterLookTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

private func directory(_ defaults: UserDefaults) -> SupporterDirectory {
    SupporterDirectory(
        transport: UnusedTransport(),
        endpoints: WorkerEndpoints(baseURL: URL(string: "https://example.com/v1/embr")!),
        defaults: defaults
    )
}

@Suite struct SupporterDirectoryTests {
    @Test func aSupportersLookComesFromTheirProfile() {
        let supporters = directory(freshDefaults())
        supporters.insert("42", profile: SupporterAPI.Profile(number: 7, color: "gold", nameStyle: "glow"))

        let look = supporters.look(for: "42")
        #expect(look?.color == .gold)
        #expect(look?.nameStyle == .glow)
        #expect(look?.number == 7)
        #expect(look?.badge.version == "gold")
        #expect(supporters.look(for: "43") == nil)
        #expect(supporters.look(for: "") == nil)
        #expect(supporters.count == 1)
    }

    @Test func aColorOrStyleThisBuildDoesNotKnowFallsBackToTheDefaultLook() {
        let supporters = directory(freshDefaults())
        supporters.insert("42", profile: SupporterAPI.Profile(number: nil, color: "chartreuse", nameStyle: "sparkle"))

        let look = supporters.look(for: "42")
        #expect(look?.color == .violet)
        #expect(look?.nameStyle == .twitch)
    }

    @Test func theListSurvivesARelaunch() {
        let defaults = freshDefaults()
        directory(defaults).insert("42", profile: SupporterAPI.Profile(number: 3, color: "mint", nameStyle: "color"))

        let relaunched = directory(defaults)
        #expect(relaunched.look(for: "42")?.color == .mint)
        #expect(relaunched.look(for: "42")?.number == 3)
        #expect(relaunched.count == 1)
    }

    @Test func theIDsAnEarlierBuildKeptStillShowTheDefaultBadge() {
        let defaults = freshDefaults()
        defaults.set(["9", "10"], forKey: "supporters.directory.v1")

        let supporters = directory(defaults)
        #expect(supporters.contains("9"))
        #expect(supporters.look(for: "10")?.color == .violet)
        #expect(supporters.count == 2)
    }

    @Test func pinningAnotherAccountTakesTheBadgeOffThePreviousOne() {
        let supporters = directory(freshDefaults())
        supporters.pin("1", profile: SupporterAPI.Profile(number: 4, color: "gold", nameStyle: "glow"))
        supporters.pin("2", profile: SupporterAPI.Profile(number: 4, color: "gold", nameStyle: "glow"))

        #expect(!supporters.contains("1"))
        #expect(supporters.look(for: "2")?.number == 4)
        #expect(supporters.count == 1)

        supporters.unpin()
        #expect(!supporters.contains("2"))
        #expect(supporters.count == 0)
    }

    @Test func everyChangeToALookMovesTheRevisionSoOpenChatsRedraw() {
        let supporters = directory(freshDefaults())
        let start = supporters.revision
        supporters.insert("5", profile: SupporterAPI.Profile(number: nil, color: "mint", nameStyle: "color"))
        let inserted = supporters.revision
        supporters.remove("5")
        supporters.remove("5")

        #expect(inserted > start)
        #expect(supporters.revision == inserted + 1)
        #expect(supporters.count == 0)
    }

    @Test func insertingTheSameSupporterAgainUpdatesWithoutCountingTwice() {
        let supporters = directory(freshDefaults())
        supporters.insert("42", profile: SupporterAPI.Profile(number: 3, color: "mint", nameStyle: "color"))
        supporters.insert("42", profile: SupporterAPI.Profile(number: 3, color: "rose", nameStyle: "glow"))

        #expect(supporters.count == 1)
        #expect(supporters.look(for: "42")?.color == .rose)
    }
}

@Suite struct SupporterThemeTests {
    private func traits(_ theme: SupporterTheme, dark: Bool) -> UITraitCollection {
        UITraitCollection().modifyingTraits { traits in
            traits[SupporterThemeTrait.self] = theme
            traits.userInterfaceStyle = dark ? .dark : .light
        }
    }

    private func white(_ color: UIColor) -> CGFloat {
        var white: CGFloat = 0, alpha: CGFloat = 0
        color.getWhite(&white, alpha: &alpha)
        return white
    }

    @Test func pageColorsFollowTheThemeTheViewsCarry() {
        let standard = Theme.background.resolvedColor(with: traits(.standard, dark: true))
        let oled = Theme.background.resolvedColor(with: traits(.oled, dark: true))
        let midnight = Theme.background.resolvedColor(with: traits(.midnight, dark: true))

        #expect(abs(white(standard) - 0.07) < 0.01)
        #expect(white(oled) == 0)
        #expect(midnight != standard)
        #expect(Theme.surface.resolvedColor(with: traits(.ember, dark: false)) != Theme.surface.resolvedColor(with: traits(.ember, dark: true)))
    }

    @Test func everyThemeHasItsOwnDarkPage() {
        let pages = SupporterTheme.allCases.map { Theme.background.resolvedColor(with: traits($0, dark: true)) }
        #expect(Set(pages.map { $0.description }).count == SupporterTheme.allCases.count)
    }

    @Test func chatLaysOutAgainOnlyWhenSomethingItDrawsChanged() {
        var settings = Settings.default
        let before = settings.chatLayoutKey
        settings.autoplay.toggle()
        #expect(settings.chatLayoutKey == before)
        settings.supporterNameEffects = false
        #expect(settings.chatLayoutKey != before)
    }

    @Test func chatFontsUseTheirSystemDesign() {
        #expect(SupporterChatFont.mono.font(ofSize: 14).fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
        #expect(SupporterChatFont.standard.font(ofSize: 14) == UIFont.systemFont(ofSize: 14))
        #expect(SupporterChatFont.serif.font(ofSize: 14, weight: .bold).fontName != UIFont.boldSystemFont(ofSize: 14).fontName)
    }
}

@Suite struct SupporterChatLookTests {
    private let author = ChatUser(id: "777", login: "flamefan", displayName: "FlameFan", color: ChatColor(red: 0, green: 200, blue: 0))

    private func layout(style: SupporterAPI.NameStyle) -> LaidOutMessage {
        let preview = MessageLayout.Preview(
            authorID: author.id,
            look: SupporterDirectory.Look(badge: SupporterAccent.rose.badge, color: .rose, nameStyle: style, number: 5),
            font: .rounded
        )
        let message = ChatMessage(id: "m", channelID: "c", timestamp: Date(), author: author, fragments: [.text("hello")])
        return MessageLayout(width: 320, settings: .default, catalog: EmoteCatalog(), badges: BadgeCatalog(), preview: preview).layout(message)
    }

    @Test func aGlowingNameCarriesALightAroundItAndTheFlameBadge() {
        let laidOut = layout(style: .glow)
        let shadow = laidOut.attributedText.attribute(.shadow, at: laidOut.usernameRange.location, effectiveRange: nil) as? NSShadow

        #expect(shadow != nil)
        #expect(laidOut.badgePlacements.last?.badge.setID == "embr-supporter")
        #expect(laidOut.badgePlacements.last?.badge.version == "rose")
    }

    @Test func aTwitchColoredNameHasNoGlowButKeepsTheBadge() {
        let laidOut = layout(style: .twitch)
        let shadow = laidOut.attributedText.attribute(.shadow, at: laidOut.usernameRange.location, effectiveRange: nil)

        #expect(shadow == nil)
        #expect(laidOut.badgePlacements.count == 1)
    }

    @Test func thePreviewsChatFontReachesTheMessage() {
        let font = layout(style: .color).attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        let size = font?.pointSize ?? 14
        #expect(font != nil)
        #expect(font?.fontName != UIFont.systemFont(ofSize: size, weight: .bold).fontName)
    }
}
