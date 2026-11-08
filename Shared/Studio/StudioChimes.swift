import AVFoundation
import EmbrCore
import MidgarCore

/// Studio's alert sounds, made on the device from a few soft tones so the app ships no audio files. They mix with
/// whatever else the device is playing and have their own volume.
@MainActor
final class StudioChimes {
    static let shared = StudioChimes()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
    private var buffers: [StudioSound: AVAudioPCMBuffer] = [:]
    private var prepared = false
    private var lastPlayed: [StudioSound: Date] = [:]

    func play(_ sound: StudioSound, volume: Float) {
        guard volume > 0 else { return }
        let now = Date()
        if let last = lastPlayed[sound], now.timeIntervalSince(last) < 1.5 { return }
        lastPlayed[sound] = now
        guard prepare(), let buffer = buffer(for: sound) else { return }
        player.volume = min(max(volume, 0), 1)
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func prepare() -> Bool {
        if prepared { return true }
        guard let format else { return false }
        do {
            let session = AVAudioSession.sharedInstance()
            if session.category != .playback {
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            }
            try session.setActive(true)
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            try engine.start()
            prepared = true
            return true
        } catch {
            MidgarLog.notice("Studio chimes unavailable: \(error)", category: .studio)
            return false
        }
    }

    private func buffer(for sound: StudioSound) -> AVAudioPCMBuffer? {
        if let cached = buffers[sound] { return cached }
        guard let format, let buffer = Self.render(Self.notes(for: sound), format: format) else { return nil }
        buffers[sound] = buffer
        return buffer
    }

    /// Each sound as notes: a frequency, when it starts and how long it rings, in seconds.
    private static func notes(for sound: StudioSound) -> [(frequency: Double, start: Double, length: Double)] {
        switch sound {
        case .adWarning: [(880, 0, 0.18), (880, 0.24, 0.3)]
        case .raid: [(523.25, 0, 0.2), (659.25, 0.12, 0.2), (783.99, 0.24, 0.2), (1046.5, 0.36, 0.5)]
        case .hypeTrain: [(659.25, 0, 0.15), (783.99, 0.1, 0.15), (987.77, 0.2, 0.4)]
        case .gift: [(783.99, 0, 0.25), (1174.66, 0.15, 0.45)]
        case .bits: [(1318.51, 0, 0.12), (1567.98, 0.08, 0.3)]
        case .subscription: [(587.33, 0, 0.22), (880, 0.14, 0.4)]
        case .goal: [(523.25, 0, 0.2), (659.25, 0.15, 0.2), (783.99, 0.3, 0.6)]
        case .follow: [(987.77, 0, 0.25)]
        case .redemption: [(698.46, 0, 0.2), (880, 0.12, 0.3)]
        case .alarm: [(440, 0, 0.2), (349.23, 0.25, 0.2), (440, 0.5, 0.2), (349.23, 0.75, 0.3)]
        }
    }

    private static func render(_ notes: [(frequency: Double, start: Double, length: Double)], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let total = (notes.map { $0.start + $0.length }.max() ?? 0) + 0.05
        let frames = AVAudioFrameCount(total * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames), let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for frame in 0..<Int(frames) { samples[frame] = 0 }
        for note in notes {
            let first = Int(note.start * rate)
            let count = Int(note.length * rate)
            for index in 0..<count where first + index < Int(frames) {
                let t = Double(index) / rate
                let attack = min(1, t / 0.008)
                let decay = exp(-t * 6 / note.length)
                let tone = sin(2 * .pi * note.frequency * t) * 0.8 + sin(4 * .pi * note.frequency * t) * 0.12
                samples[first + index] += Float(tone * attack * decay * 0.28)
            }
        }
        return buffer
    }
}
