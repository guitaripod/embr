import Combine
import Foundation
import Testing
import UIKit

@testable import Embr

@MainActor
private func freshStore() -> SettingsStore {
    let name = "SettingsPageTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return SettingsStore(defaults: defaults)
}

@MainActor
@Suite struct SettingsItemTests {
    @Test func aRowIsRedrawnOnlyWhenWhatItShowsChanges() {
        let on = SettingsItem(id: "a", title: "Haptics", kind: .toggle(isOn: true) { _ in })
        let onAgain = SettingsItem(id: "a", title: "Haptics", kind: .toggle(isOn: true) { _ in })
        let off = SettingsItem(id: "a", title: "Haptics", kind: .toggle(isOn: false) { _ in })
        #expect(on.signature == onAgain.signature)
        #expect(on.signature != off.signature)

        let dark = SettingsItem(id: "t", title: "Theme", kind: .menu(value: "Dark", choices: []))
        let light = SettingsItem(id: "t", title: "Theme", kind: .menu(value: "Light", choices: []))
        #expect(dark.signature != light.signature)
    }

    @Test func onlyRowsThatDoSomethingHighlight() {
        #expect(SettingsItem(id: "l", title: "Link", kind: .link(value: nil) { _ in }).isSelectable)
        #expect(SettingsItem(id: "a", title: "Rate", kind: .action(role: .accent) { _, _ in }).isSelectable)
        #expect(!SettingsItem(id: "s", title: "Switch", kind: .toggle(isOn: true) { _ in }).isSelectable)
        #expect(!SettingsItem(id: "v", title: "Version", kind: .value("1.0")).isSelectable)
    }
}

@MainActor
@Suite struct SettingsPageTests {
    @Test func aPageRebuildsItsRowsWhenItsSettingsChange() {
        let changes = PassthroughSubject<Void, Never>()
        var showsExtra = false
        let page = SettingsPageViewController(title: "Test", changes: changes.eraseToAnyPublisher()) { _ in
            var items = [SettingsItem(id: "one", title: "One", kind: .toggle(isOn: showsExtra) { _ in })]
            if showsExtra { items.append(SettingsItem(id: "two", title: "Two", kind: .value("2"))) }
            return [SettingsSection(id: "main", items: items)]
        }
        page.loadViewIfNeeded()
        #expect(page.collectionView.numberOfItems(inSection: 0) == 1)

        showsExtra = true
        page.reload()
        #expect(page.collectionView.numberOfItems(inSection: 0) == 2)
    }

    @Test func searchFindsEverySettingWithWhereItLives() {
        let settings = SettingsViewController(store: freshStore())
        let entries = settings.searchEntries?() ?? []
        let muted = entries.first { $0.item.id == "mutedKeywords" }
        #expect(muted?.path == String(localized: "Safety & Moderation"))
        #expect(entries.contains { $0.item.id == "haptics" })
        #expect(entries.contains { $0.item.id == "page.chat" })
        #expect(!entries.contains { $0.item.id == "moreApps" })
        #expect(!entries.contains { $0.item.id.hasPrefix("account.") && $0.item.id != "account.card" })
    }

    @Test func onlySettingsTheAppReadsAreOffered() {
        let settings = SettingsViewController(store: freshStore())
        let ids = Set((settings.searchEntries?() ?? []).map(\.item.id))
        #expect(!ids.contains("autoplay"))
        #expect(!ids.contains("chatDelaySeconds"))
        #expect(!ids.contains("autoSyncChatDelay"))
        #expect(ids.contains("recentMessagesBackfill"))
        #expect(ids.contains("openLinksInApp"))
    }
}
