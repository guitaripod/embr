import UIKit

#if os(iOS)
/// Haptics through generators kept for the life of the app and prepared again after each use, so a tap, a send or a
/// swipe crossing its threshold is felt the moment it happens rather than after the Taptic Engine wakes.
@MainActor
enum Haptics {
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    private static var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]

    static func selection(_ store: SettingsStore = .shared) {
        guard store.current.hapticsEnabled else { return }
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light, store: SettingsStore = .shared) {
        guard store.current.hapticsEnabled else { return }
        let generator = impactGenerator(style)
        generator.impactOccurred()
        generator.prepare()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType, store: SettingsStore = .shared) {
        guard store.current.hapticsEnabled else { return }
        notificationGenerator.notificationOccurred(type)
        notificationGenerator.prepare()
    }

    /// Wakes the engine for an impact that is about to happen, as when a drag starts toward a threshold.
    static func prepareImpact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        impactGenerator(style).prepare()
    }

    private static func impactGenerator(_ style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        if let generator = impactGenerators[style] { return generator }
        let generator = UIImpactFeedbackGenerator(style: style)
        impactGenerators[style] = generator
        return generator
    }
}
#endif
