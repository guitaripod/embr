import UIKit

@MainActor
enum Haptics {
    static func selection(_ store: SettingsStore = .shared) {
        guard store.current.hapticsEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light, store: SettingsStore = .shared) {
        guard store.current.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType, store: SettingsStore = .shared) {
        guard store.current.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
