import MediaPlayer
import UIKit
import MidgarCore

extension VideoViewController {
    func setNowPlayingMetadata(title: String?, channelName: String?, avatarURL: URL? = nil) {
        nowPlayingTitle = title
        nowPlayingChannelName = channelName
        updateNowPlaying()
        loadArtworkIfNeeded(avatarURL)
    }

    private func loadArtworkIfNeeded(_ url: URL?) {
        guard let url, url != artworkURL else { return }
        artworkURL = url
        Task { [weak self, imageLoader] in
            let image = await imageLoader.image(for: url, targetScale: 2.0)
            guard let self, self.artworkURL == url else { return }
            guard let image else {
                self.artworkURL = nil
                return
            }
            self.nowPlayingArtwork = Self.makeArtwork(image)
            self.updateNowPlaying()
        }
    }

    private nonisolated static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    private var defaultNowPlayingTitle: String {
        switch source {
        case .live(let login): return login
        case .vod: return String(localized: "Video")
        case .clip: return String(localized: "Clip")
        }
    }

    private var defaultNowPlayingArtist: String? {
        if case .live(let login) = source { return login }
        return nil
    }

    func updateNowPlaying() {
        guard !didTeardownPlayer else { return }
        nowPlaying.update(
            title: nowPlayingTitle ?? defaultNowPlayingTitle,
            artist: nowPlayingChannelName ?? defaultNowPlayingArtist,
            isLive: !isSeekableSource,
            elapsed: lastProgress.current,
            duration: lastProgress.duration,
            isPlaying: currentState == .playing,
            rate: currentRate,
            artwork: nowPlayingArtwork
        )
    }

    func registerRemoteCommands() {
        nowPlaying.register(
            play: { [weak self] in self?.remotePlay() },
            pause: { [weak self] in self?.player.pause() },
            toggle: { [weak self] in self?.remoteTogglePlayPause() }
        )
    }

    private func remotePlay() {
        if case .live = source { player.seekToLive() }
        player.play()
    }

    private func remoteTogglePlayPause() {
        if currentState == .playing {
            player.pause()
        } else {
            remotePlay()
        }
    }
}
