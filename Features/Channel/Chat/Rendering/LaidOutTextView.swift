import UIKit

/// Draws a message's text with the same TextKit 1 layout `MessageLayout` measured it with, so emotes and badges
/// placed from that measurement sit exactly where the words are. tvOS's `UILabel` breaks some lines differently
/// (a trailing emote stays on the first line there), which would leave the emote images a line off.
final class LaidOutTextView: UIView {
    var attributedText: NSAttributedString? {
        didSet { setNeedsDisplay() }
    }

    /// Space around the text on every side, for the light of a glowing name.
    var textInset: CGFloat = 0 {
        didSet { if textInset != oldValue { setNeedsDisplay() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let attributedText, bounds.width > textInset * 2 else { return }
        let storage = NSTextStorage(attributedString: attributedText)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: bounds.width - textInset * 2, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        let glyphs = manager.glyphRange(for: container)
        let origin = CGPoint(x: textInset, y: textInset)
        manager.drawBackground(forGlyphRange: glyphs, at: origin)
        manager.drawGlyphs(forGlyphRange: glyphs, at: origin)
    }
}
