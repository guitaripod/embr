import UIKit

/// An image view with the system focus treatment (lift, parallax and sheen while an ancestor cell is focused) that
/// loads its picture through `ImageLoader`, showing a placeholder until it arrives and fading it in.
///
/// It must not clip to its bounds, because clipping switches the focus effect off; the corners come from the layer.
final class TVArtworkView: UIImageView {
    enum Shape {
        case rounded
        case circle
    }

    private let shape: Shape
    private let placeholderSymbol: String
    private var loadTask: Task<Void, Never>?
    private var loadedURL: URL?

    init(shape: Shape = .rounded, placeholderSymbol: String) {
        self.shape = shape
        self.placeholderSymbol = placeholderSymbol
        super.init(frame: .zero)
        contentMode = .scaleAspectFill
        adjustsImageWhenAncestorFocused = true
        switch shape {
        case .rounded:
            layer.cornerCurve = .continuous
            layer.cornerRadius = TVMetrics.cornerRadius
        case .circle:
            masksFocusEffectToContents = true
        }
        showPlaceholder()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    isolated deinit {
        loadTask?.cancel()
    }

    func setImage(_ url: URL?) {
        guard url != loadedURL || image == nil else { return }
        loadTask?.cancel()
        loadedURL = url
        guard let url else {
            showPlaceholder()
            return
        }
        if let cached = AppContainer.shared.images.cachedImage(for: url) {
            display(cached, animated: false)
            return
        }
        showPlaceholder()
        let images = AppContainer.shared.images
        loadTask = Task { [weak self] in
            let loaded = await images.image(for: url, targetScale: 1)
            guard !Task.isCancelled, let self, self.loadedURL == url, let loaded else { return }
            self.display(loaded, animated: true)
        }
    }

    func reset() {
        loadTask?.cancel()
        loadTask = nil
        loadedURL = nil
        showPlaceholder()
    }

    private func showPlaceholder() {
        image = TVPlaceholder.image(symbol: placeholderSymbol, circular: shape == .circle)
    }

    private func display(_ picture: UIImage, animated: Bool) {
        let shown = shape == .circle ? TVPlaceholder.circular(picture) : picture
        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            image = shown
            return
        }
        UIView.transition(with: self, duration: TVMetrics.Duration.fade, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            self.image = shown
        }
    }
}

/// Placeholder art: a symbol on a soft gradient, cached per symbol and shape.
@MainActor
enum TVPlaceholder {
    private static var cache: [String: UIImage] = [:]
    private static let size = CGSize(width: 480, height: 270)

    static func image(symbol: String, circular: Bool) -> UIImage {
        let key = "\(symbol)|\(circular)"
        if let cached = cache[key] { return cached }
        let canvas = circular ? CGSize(width: 270, height: 270) : size
        let image = UIGraphicsImageRenderer(size: canvas).image { context in
            let top = UIColor(white: 0.22, alpha: 1)
            let bottom = UIColor(white: 0.12, alpha: 1)
            let space = CGColorSpaceCreateDeviceRGB()
            if circular {
                context.cgContext.addEllipse(in: CGRect(origin: .zero, size: canvas))
                context.cgContext.clip()
            }
            if let gradient = CGGradient(colorsSpace: space, colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: canvas.height), options: [])
            }
            let configuration = UIImage.SymbolConfiguration(pointSize: canvas.height * 0.28, weight: .regular)
            if let glyph = UIImage(systemName: symbol, withConfiguration: configuration)?.withTintColor(UIColor(white: 1, alpha: 0.35), renderingMode: .alwaysOriginal) {
                let origin = CGPoint(x: (canvas.width - glyph.size.width) / 2, y: (canvas.height - glyph.size.height) / 2)
                glyph.draw(at: origin)
            }
        }
        cache[key] = image
        return image
    }

    /// A square crop of `picture` inside a circle, for avatars, which keeps the focus effect round.
    static func circular(_ picture: UIImage) -> UIImage {
        let side = min(picture.size.width, picture.size.height)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            context.cgContext.addEllipse(in: CGRect(x: 0, y: 0, width: side, height: side))
            context.cgContext.clip()
            picture.draw(at: CGPoint(x: (side - picture.size.width) / 2, y: (side - picture.size.height) / 2))
        }
    }
}
