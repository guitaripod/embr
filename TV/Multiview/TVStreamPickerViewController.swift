import UIKit
import EmbrCore

/// Chooses a live stream to add to the multiview: favorites and follows first, then the top streams.
final class TVStreamPickerViewController: TVShelfViewController {
    private let excluding: Set<String>
    private let onPick: (LiveStream) -> Void

    init(excluding: Set<String>, onPick: @escaping (LiveStream) -> Void) {
        self.excluding = excluding
        self.onPick = onPick
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var offersContextMenu: Bool { false }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
    }

    override func load() async {
        stateView.showLoading()
        await TVLiveDirectory.shared.refreshIfStale()
        let mine = TVLiveDirectory.shared.liveNow.filter { !excluding.contains($0.userID) }
        let top = ((try? await AppContainer.shared.api.topStreams(after: nil, first: 30).items) ?? [])
            .filter { stream in !excluding.contains(stream.userID) && !mine.contains { $0.userID == stream.userID } }
        apply([
            TVShelf(id: "mine", title: String(localized: "Your Channels"), style: .streams, items: mine.map(TVShelfItem.stream)),
            TVShelf(id: "top", title: String(localized: "Top Live"), style: .streams, items: top.map(TVShelfItem.stream)),
        ])
        if mine.isEmpty && top.isEmpty {
            stateView.show(symbol: "tv", title: String(localized: "Nothing else is live"), message: nil)
        }
    }

    override func didSelect(_ item: TVShelfItem) {
        guard case .stream(let stream) = item else { return }
        dismiss(animated: true) { [onPick] in onPick(stream) }
    }
}
