import TVServices
import EmbrCore
import MidgarCore

/// The Apple TV Top Shelf: the person's live favorites and followed channels as a carousel, each with the stream's
/// picture, and a muted live preview behind the focused one when previews are on. Play opens the stream, select opens
/// the channel. With nothing live it returns nothing and the system shows Embr's static Top Shelf image.
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping @Sendable ((any TVTopShelfContent)?) -> Void) {
        Task {
            let plan = await ShelfContent.plan()
            completionHandler(plan.map(ShelfContent.carousel(for:)))
        }
    }
}
