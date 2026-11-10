import Foundation

/// The screen a stream plays on while AirPlay, or a mirrored or wired display, has the picture instead of this device.
nonisolated struct ExternalRoute: Equatable, Sendable {
    let deviceName: String?

    var playingOnText: String {
        guard let deviceName, !deviceName.isEmpty else { return String(localized: "Playing on another screen") }
        return String(localized: "Playing on \(deviceName)")
    }
}
