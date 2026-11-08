#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

/// Renders Embr's flame for every place it appears outside the iPhone's main icon: the Apple TV's layered app icon and
/// Top Shelf images, the Founding Supporter chat badge and large flame in every supporter color, and the supporters'
/// alternate iPhone icons: the flame in each color, and the Midnight, Paper, Neon and Pixel designs.
///
/// Usage: swift scripts/render-brand-art.swift <output directory>

struct RGB {
    let r: CGFloat, g: CGFloat, b: CGFloat
    init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) { self.r = r / 255; self.g = g / 255; self.b = b / 255 }
    func cg(_ alpha: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: alpha) }
}

/// A flame's colors from tip to base for the outer flame, the inner flame and the glow around it.
struct Palette {
    let outer: [(CGFloat, RGB)]
    let inner: [(CGFloat, RGB)]
    let glow: RGB
    let background: (center: RGB, edge: RGB)

    static let violet = Palette(
        outer: [(0, RGB(142, 53, 245)), (0.2, RGB(164, 64, 240)), (0.4, RGB(205, 79, 217)), (0.55, RGB(237, 80, 138)),
                (0.68, RGB(249, 102, 97)), (0.82, RGB(254, 134, 63)), (1, RGB(255, 196, 110))],
        inner: [(0, RGB(255, 95, 192)), (0.19, RGB(255, 98, 190)), (0.36, RGB(255, 117, 175)), (0.45, RGB(255, 138, 168)),
                (0.54, RGB(255, 178, 167)), (0.63, RGB(255, 232, 160)), (0.72, RGB(255, 252, 150)), (0.86, RGB(255, 255, 214)),
                (1, RGB(255, 255, 255))],
        glow: RGB(150, 72, 255),
        background: (RGB(30, 22, 44), RGB(10, 8, 15))
    )

    /// The same flame with its hues turned: the supporters' accent colors.
    static func tinted(outer: [RGB], inner: [RGB], glow: RGB, center: RGB) -> Palette {
        let outerStops: [CGFloat] = [0, 0.2, 0.4, 0.55, 0.68, 0.82, 1]
        let innerStops: [CGFloat] = [0, 0.4, 0.58, 0.72, 1]
        return Palette(
            outer: Array(zip(outerStops, outer)),
            inner: Array(zip(innerStops, inner)),
            glow: glow,
            background: (center, RGB(10, 8, 14))
        )
    }

    static let ember = tinted(
        outer: [RGB(214, 38, 38), RGB(232, 58, 40), RGB(244, 86, 42), RGB(250, 118, 46), RGB(253, 148, 52), RGB(255, 182, 66), RGB(255, 226, 120)],
        inner: [RGB(255, 132, 64), RGB(255, 176, 92), RGB(255, 214, 128), RGB(255, 245, 180), RGB(255, 255, 248)],
        glow: RGB(255, 84, 40), center: RGB(40, 18, 14)
    )
    static let rose = tinted(
        outer: [RGB(196, 40, 160), RGB(222, 52, 150), RGB(242, 70, 140), RGB(250, 96, 140), RGB(255, 126, 150), RGB(255, 162, 168), RGB(255, 210, 206)],
        inner: [RGB(255, 120, 190), RGB(255, 160, 200), RGB(255, 200, 216), RGB(255, 236, 236), RGB(255, 255, 255)],
        glow: RGB(255, 70, 160), center: RGB(40, 16, 32)
    )
    static let gold = tinted(
        outer: [RGB(214, 120, 24), RGB(228, 146, 30), RGB(240, 172, 40), RGB(246, 192, 56), RGB(250, 210, 80), RGB(253, 226, 112), RGB(255, 244, 178)],
        inner: [RGB(255, 210, 90), RGB(255, 226, 130), RGB(255, 240, 170), RGB(255, 250, 214), RGB(255, 255, 250)],
        glow: RGB(255, 176, 40), center: RGB(36, 26, 10)
    )
    static let mint = tinted(
        outer: [RGB(20, 150, 140), RGB(26, 176, 146), RGB(34, 200, 150), RGB(60, 218, 160), RGB(98, 232, 176), RGB(146, 242, 198), RGB(210, 252, 228)],
        inner: [RGB(90, 236, 196), RGB(140, 244, 210), RGB(186, 250, 226), RGB(226, 254, 242), RGB(255, 255, 255)],
        glow: RGB(30, 220, 160), center: RGB(10, 32, 28)
    )
    static let ocean = tinted(
        outer: [RGB(52, 60, 230), RGB(54, 92, 240), RGB(60, 128, 248), RGB(70, 158, 252), RGB(92, 188, 255), RGB(132, 214, 255), RGB(204, 240, 255)],
        inner: [RGB(100, 170, 255), RGB(140, 200, 255), RGB(180, 224, 255), RGB(220, 242, 255), RGB(255, 255, 255)],
        glow: RGB(60, 120, 255), center: RGB(12, 18, 44)
    )
    static let frost = tinted(
        outer: [RGB(96, 140, 220), RGB(110, 170, 232), RGB(126, 198, 240), RGB(150, 216, 246), RGB(178, 230, 250), RGB(208, 240, 252), RGB(240, 252, 255)],
        inner: [RGB(170, 226, 255), RGB(196, 236, 255), RGB(220, 246, 255), RGB(240, 252, 255), RGB(255, 255, 255)],
        glow: RGB(130, 200, 255), center: RGB(18, 26, 38)
    )
}

/// The outer and inner flame on the 1024 pt iPhone icon's grid, each as four cubic curves fitted to a trace of the icon:
/// tip to the widest point on the left, round the base, up to the widest point on the right and back to the sharp tip.
enum FlameShape {
    struct Curve {
        let control1: CGPoint
        let control2: CGPoint
        let end: CGPoint
    }

    struct Outline {
        let tip: CGPoint
        let curves: [Curve]
    }

    static let outer = Outline(tip: CGPoint(x: 569, y: 142), curves: [
        Curve(control1: CGPoint(x: 366, y: 305), control2: CGPoint(x: 234.5, y: 410), end: CGPoint(x: 234.5, y: 590)),
        Curve(control1: CGPoint(x: 234.5, y: 740), control2: CGPoint(x: 349, y: 823), end: CGPoint(x: 519, y: 823)),
        Curve(control1: CGPoint(x: 680, y: 823), control2: CGPoint(x: 801.5, y: 730), end: CGPoint(x: 801.5, y: 575)),
        Curve(control1: CGPoint(x: 801.5, y: 405), control2: CGPoint(x: 722.6, y: 313), end: CGPoint(x: 569, y: 142)),
    ])

    static let inner = Outline(tip: CGPoint(x: 544, y: 436), curves: [
        Curve(control1: CGPoint(x: 461, y: 508), control2: CGPoint(x: 379, y: 558), end: CGPoint(x: 379, y: 668)),
        Curve(control1: CGPoint(x: 379, y: 730), control2: CGPoint(x: 445, y: 776), end: CGPoint(x: 518, y: 776)),
        Curve(control1: CGPoint(x: 600, y: 776), control2: CGPoint(x: 656, y: 720), end: CGPoint(x: 656, y: 655)),
        Curve(control1: CGPoint(x: 656, y: 560), control2: CGPoint(x: 608, y: 513), end: CGPoint(x: 544, y: 436)),
    ])

    static let bounds = CGRect(x: 234.5, y: 142, width: 567, height: 681)

    static func path(_ outline: Outline, transform: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        path.move(to: outline.tip, transform: transform)
        for curve in outline.curves {
            path.addCurve(to: curve.end, control1: curve.control1, control2: curve.control2, transform: transform)
        }
        path.closeSubpath()
        return path
    }
}

/// Draws into a bitmap whose origin is at the top left, like the measured points.
func render(width: Int, height: Int, opaque: Bool, _ draw: (CGContext) -> Void) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)!
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    context.interpolationQuality = .high
    context.setShouldAntialias(true)
    draw(context)
    return context.makeImage()!
}

func save(_ image: CGImage, _ url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

func gradient(_ stops: [(CGFloat, RGB)], alpha: CGFloat = 1) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: stops.map { $0.1.cg(alpha) } as CFArray,
        locations: stops.map { $0.0 }
    )!
}

/// The flame fitted into `rect` (its height decides the scale), with or without its glow and inner flame.
struct FlameDrawing {
    let palette: Palette
    let rect: CGRect
    var glow = true
    var outer = true
    var inner = true

    var transform: CGAffineTransform {
        let scale = rect.height / FlameShape.bounds.height
        let width = FlameShape.bounds.width * scale
        let originX = rect.midX - width / 2 - FlameShape.bounds.minX * scale
        let originY = rect.minY - FlameShape.bounds.minY * scale
        return CGAffineTransform(translationX: originX, y: originY).scaledBy(x: scale, y: scale)
    }

    var scale: CGFloat { rect.height / FlameShape.bounds.height }

    func draw(in context: CGContext) {
        let outerPath = FlameShape.path(FlameShape.outer, transform: transform)
        let innerPath = FlameShape.path(FlameShape.inner, transform: transform)
        let top = rect.minY
        let bottom = rect.maxY
        if glow {
            for (blur, alpha) in [(130.0, 0.7), (60.0, 0.6)] as [(CGFloat, CGFloat)] {
                context.saveGState()
                context.setShadow(offset: .zero, blur: blur * scale, color: palette.glow.cg(alpha))
                context.addPath(outerPath)
                context.setFillColor(palette.glow.cg(1))
                context.fillPath()
                context.restoreGState()
            }
        }
        if outer {
            context.saveGState()
            context.addPath(outerPath)
            context.clip()
            context.drawLinearGradient(gradient(palette.outer), start: CGPoint(x: rect.midX, y: top), end: CGPoint(x: rect.midX, y: bottom), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            let warm = palette.inner[palette.inner.count - 3].1
            context.drawRadialGradient(
                falloff(warm, 0.7),
                startCenter: CGPoint(x: rect.midX, y: bottom - rect.height * 0.08), startRadius: 0,
                endCenter: CGPoint(x: rect.midX, y: bottom - rect.height * 0.08), endRadius: rect.height * 0.36,
                options: []
            )
            context.restoreGState()
        }
        if inner {
            let innerTop = transform.ty + FlameShape.inner.tip.y * scale
            context.saveGState()
            context.addPath(innerPath)
            context.clip()
            context.drawLinearGradient(gradient(palette.inner), start: CGPoint(x: rect.midX, y: innerTop), end: CGPoint(x: rect.midX, y: bottom - 46 * scale), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            context.drawRadialGradient(
                falloff(RGB(255, 255, 255), 0.85),
                startCenter: CGPoint(x: rect.midX, y: bottom - 60 * scale), startRadius: 0,
                endCenter: CGPoint(x: rect.midX, y: bottom - 60 * scale), endRadius: 120 * scale,
                options: []
            )
            context.restoreGState()
        }
    }
}

/// A two-stop falloff from `color` at `alpha` to transparent, for the warm light at the base.
func falloff(_ color: RGB, _ alpha: CGFloat) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color.cg(alpha), color.cg(0)] as CFArray, locations: [0, 1])!
}

func background(_ palette: Palette, in context: CGContext, size: CGSize, focus: CGPoint) {
    context.setFillColor(palette.background.edge.cg())
    context.fill(CGRect(origin: .zero, size: size))
    let radius = max(size.width, size.height) * 0.75
    context.drawRadialGradient(
        gradient([(0, palette.background.center), (1, palette.background.edge)]),
        startCenter: focus, startRadius: 0, endCenter: focus, endRadius: radius, options: [.drawsAfterEndLocation]
    )
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "brand-art")
let violet = Palette.violet

/// The Apple TV app icon in three parallax layers: the night behind, the flame with its glow, the bright inner flame.
func tvIcon(width: Int, height: Int, scale: Int, folder: String) {
    let w = width * scale, h = height * scale
    let size = CGSize(width: w, height: h)
    let flameHeight = CGFloat(h) * 0.74
    let rect = CGRect(x: CGFloat(w) / 2 - flameHeight / 2, y: (CGFloat(h) - flameHeight) / 2, width: flameHeight, height: flameHeight)
    let suffix = scale == 1 ? "@1x" : "@2x"
    save(render(width: w, height: h, opaque: true) { background(violet, in: $0, size: size, focus: CGPoint(x: size.width / 2, y: size.height * 0.62)) },
         output.appendingPathComponent("\(folder)/back\(suffix).png"))
    save(render(width: w, height: h, opaque: false) { FlameDrawing(palette: violet, rect: rect, inner: false).draw(in: $0) },
         output.appendingPathComponent("\(folder)/middle\(suffix).png"))
    save(render(width: w, height: h, opaque: false) { FlameDrawing(palette: violet, rect: rect, glow: false, outer: false).draw(in: $0) },
         output.appendingPathComponent("\(folder)/front\(suffix).png"))
}

/// The Top Shelf picture behind the app icon: the flame, the name and what Embr Studio is.
func topShelf(width: Int, height: Int, scale: Int, name: String) {
    let w = width * scale, h = height * scale
    let size = CGSize(width: w, height: h)
    let image = render(width: w, height: h, opaque: true) { context in
        let flameHeight = CGFloat(h) * 0.62
        let groupStart = (size.width - CGFloat(h) * 1.4) / 2
        let flameCenter = groupStart + CGFloat(h) * 0.26
        background(violet, in: context, size: size, focus: CGPoint(x: flameCenter, y: size.height * 0.55))
        let rect = CGRect(x: flameCenter - flameHeight / 2, y: (CGFloat(h) - flameHeight) / 2, width: flameHeight, height: flameHeight)
        FlameDrawing(palette: violet, rect: rect).draw(in: context)
        let title = NSAttributedString(string: "Embr", attributes: [
            .font: NSFont.systemFont(ofSize: CGFloat(h) * 0.2, weight: .heavy),
            .foregroundColor: NSColor.white,
            .kern: -CGFloat(h) * 0.004,
        ])
        let line = NSAttributedString(string: "Studio: the control room for your stream", attributes: [
            .font: NSFont.systemFont(ofSize: CGFloat(h) * 0.058, weight: .medium),
            .foregroundColor: NSColor(white: 1, alpha: 0.62),
        ])
        let graphics = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let textX = groupStart + CGFloat(h) * 0.58
        title.draw(at: CGPoint(x: textX, y: CGFloat(h) * 0.30))
        line.draw(at: CGPoint(x: textX + CGFloat(h) * 0.01, y: CGFloat(h) * 0.56))
        NSGraphicsContext.restoreGraphicsState()
    }
    save(image, output.appendingPathComponent("topshelf/\(name)@\(scale)x.png"))
}

/// The chat badge in a supporter's flame color: the flame alone on transparency, sized for the three badge scales and
/// the large flame on the supporter screen.
func badge(_ palette: Palette, color: String, pixels: Int) {
    let image = render(width: pixels, height: pixels, opaque: false) { context in
        let inset = CGFloat(pixels) * 0.04
        let rect = CGRect(x: inset, y: inset, width: CGFloat(pixels) - inset * 2, height: CGFloat(pixels) - inset * 2)
        FlameDrawing(palette: palette, rect: rect, glow: false).draw(in: context)
    }
    let name = pixels == 600 ? "supporter-flame-\(color)" : "supporter-badge-\(color)-\(pixels)"
    save(image, output.appendingPathComponent("badge/\(name).png"))
}

/// A full iPhone icon in one of the supporters' colors.
func phoneIcon(_ palette: Palette, name: String) {
    let size = CGSize(width: 1024, height: 1024)
    let image = render(width: 1024, height: 1024, opaque: true) { context in
        background(palette, in: context, size: size, focus: CGPoint(x: 512, y: 560))
        FlameDrawing(palette: palette, rect: CGRect(x: 512 - 341, y: 140, width: 682, height: 682)).draw(in: context)
    }
    save(image, output.appendingPathComponent("icons/\(name).png"))
}

let iconFlame = CGRect(x: 512 - 341, y: 140, width: 682, height: 682)

/// Midnight: the violet flame on pure black, for OLED home screens.
func midnightIcon() {
    let image = render(width: 1024, height: 1024, opaque: true) { context in
        context.setFillColor(RGB(0, 0, 0).cg())
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        context.drawRadialGradient(
            falloff(RGB(60, 20, 110), 0.55),
            startCenter: CGPoint(x: 512, y: 700), startRadius: 0, endCenter: CGPoint(x: 512, y: 700), endRadius: 420, options: []
        )
        FlameDrawing(palette: violet, rect: iconFlame).draw(in: context)
    }
    save(image, output.appendingPathComponent("icons/midnight.png"))
}

/// Paper: the flame on warm off-white, with a soft shadow where the glow would be.
func paperIcon() {
    let size = CGSize(width: 1024, height: 1024)
    let image = render(width: 1024, height: 1024, opaque: true) { context in
        context.setFillColor(RGB(236, 228, 214).cg())
        context.fill(CGRect(origin: .zero, size: size))
        context.drawRadialGradient(
            gradient([(0, RGB(253, 250, 244)), (1, RGB(236, 228, 214))]),
            startCenter: CGPoint(x: 512, y: 420), startRadius: 0, endCenter: CGPoint(x: 512, y: 420), endRadius: 760, options: [.drawsAfterEndLocation]
        )
        let drawing = FlameDrawing(palette: violet, rect: iconFlame, glow: false)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 26), blur: 60, color: RGB(120, 60, 160).cg(0.35))
        context.addPath(FlameShape.path(FlameShape.outer, transform: drawing.transform))
        context.setFillColor(RGB(236, 228, 214).cg())
        context.fillPath()
        context.restoreGState()
        drawing.draw(in: context)
    }
    save(image, output.appendingPathComponent("icons/paper.png"))
}

/// Neon: the flame drawn as glowing tubes, the outer flame in the violet-to-gold gradient and the inner one in warm white.
func neonIcon() {
    let size = CGSize(width: 1024, height: 1024)
    let image = render(width: 1024, height: 1024, opaque: true) { context in
        background(Palette.tinted(outer: [], inner: [], glow: RGB(0, 0, 0), center: RGB(26, 12, 44)), in: context, size: size, focus: CGPoint(x: 512, y: 560))
        let drawing = FlameDrawing(palette: violet, rect: iconFlame.insetBy(dx: 30, dy: 30))
        context.drawRadialGradient(
            falloff(RGB(120, 40, 200), 0.35),
            startCenter: CGPoint(x: 512, y: 600), startRadius: 0, endCenter: CGPoint(x: 512, y: 600), endRadius: 460, options: []
        )
        let outer = FlameShape.path(FlameShape.outer, transform: drawing.transform)
        let inner = FlameShape.path(FlameShape.inner, transform: drawing.transform)
        let tubes: [(CGPath, CGFloat, [(CGFloat, RGB)], RGB)] = [
            (outer, 40, violet.outer, RGB(190, 70, 255)),
            (inner, 28, [(0, RGB(255, 140, 210)), (1, RGB(255, 240, 200))], RGB(255, 120, 190)),
        ]
        for (path, width, stops, glow) in tubes {
            for (blur, alpha) in [(90.0, 0.85), (36.0, 0.9), (12.0, 1.0)] as [(CGFloat, CGFloat)] {
                context.saveGState()
                context.setShadow(offset: .zero, blur: blur, color: glow.cg(alpha))
                context.addPath(path)
                context.setLineWidth(width)
                context.setLineJoin(.round)
                context.setStrokeColor(glow.cg(1))
                context.strokePath()
                context.restoreGState()
            }
            context.saveGState()
            context.addPath(path)
            context.setLineWidth(width)
            context.setLineJoin(.round)
            context.replacePathWithStrokedPath()
            context.clip()
            let box = path.boundingBox
            context.drawLinearGradient(gradient(stops), start: CGPoint(x: box.midX, y: box.minY), end: CGPoint(x: box.midX, y: box.maxY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            context.restoreGState()
            context.saveGState()
            context.addPath(path)
            context.setLineWidth(width * 0.28)
            context.setLineJoin(.round)
            context.setStrokeColor(RGB(255, 255, 255).cg(0.75))
            context.strokePath()
            context.restoreGState()
        }
    }
    save(image, output.appendingPathComponent("icons/neon.png"))
}

/// Snaps a small sprite to fully opaque or clear pixels in an eight-level palette and rings it with a one-pixel outline.
func outlinedSprite(_ image: CGImage, outline: RGB) -> CGImage {
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let info = CGImageAlphaInfo.premultipliedLast.rawValue
    pixels.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: info)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    func opaque(_ x: Int, _ y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else { return false }
        return pixels[(y * width + x) * 4 + 3] >= 128
    }
    var result = pixels
    for y in 0..<height {
        for x in 0..<width {
            let index = (y * width + x) * 4
            if opaque(x, y) {
                let alpha = CGFloat(pixels[index + 3]) / 255
                for channel in 0..<3 {
                    let value = min(255, CGFloat(pixels[index + channel]) / max(alpha, 0.01))
                    result[index + channel] = UInt8((value / 255 * 7).rounded() / 7 * 255)
                }
                result[index + 3] = 255
            } else if opaque(x - 1, y) || opaque(x + 1, y) || opaque(x, y - 1) || opaque(x, y + 1) {
                result[index] = UInt8(outline.r * 255)
                result[index + 1] = UInt8(outline.g * 255)
                result[index + 2] = UInt8(outline.b * 255)
                result[index + 3] = 255
            } else {
                result[index] = 0; result[index + 1] = 0; result[index + 2] = 0; result[index + 3] = 0
            }
        }
    }
    return result.withUnsafeMutableBytes { buffer in
        CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: info)!.makeImage()!
    }
}

/// Pixel: the flame drawn on a 32-pixel grid with a dark one-pixel outline, scaled up without smoothing like an old
/// game's sprite.
func pixelIcon() {
    let grid = 32
    let soft = render(width: grid, height: grid, opaque: false) { context in
        FlameDrawing(palette: violet, rect: CGRect(x: 3, y: 2, width: 26, height: 27), glow: false).draw(in: context)
    }
    let sprite = outlinedSprite(soft, outline: RGB(34, 12, 60))
    let size = CGSize(width: 1024, height: 1024)
    let image = render(width: 1024, height: 1024, opaque: true) { context in
        background(violet, in: context, size: size, focus: CGPoint(x: 512, y: 560))
        let cell: CGFloat = 24
        let side = cell * CGFloat(grid)
        let origin = CGPoint(x: (1024 - side) / 2, y: (1024 - side) / 2 + 12)
        context.saveGState()
        context.setShadow(offset: .zero, blur: 90, color: violet.glow.cg(0.7))
        context.interpolationQuality = .none
        context.translateBy(x: origin.x, y: origin.y + side)
        context.scaleBy(x: 1, y: -1)
        context.draw(sprite, in: CGRect(x: 0, y: 0, width: side, height: side))
        context.restoreGState()
    }
    save(image, output.appendingPathComponent("icons/pixel.png"))
}

tvIcon(width: 1280, height: 768, scale: 1, folder: "tv-large")
tvIcon(width: 400, height: 240, scale: 1, folder: "tv-small")
tvIcon(width: 400, height: 240, scale: 2, folder: "tv-small")
topShelf(width: 1920, height: 720, scale: 1, name: "top-shelf")
topShelf(width: 1920, height: 720, scale: 2, name: "top-shelf")
topShelf(width: 2320, height: 720, scale: 1, name: "top-shelf-wide")
topShelf(width: 2320, height: 720, scale: 2, name: "top-shelf-wide")
let colors: [(Palette, String)] = [(.violet, "violet"), (.ember, "ember"), (.rose, "rose"), (.gold, "gold"), (.mint, "mint"), (.ocean, "ocean"), (.frost, "frost")]
for (palette, name) in colors {
    for pixels in [18, 36, 72, 600] { badge(palette, color: name, pixels: pixels) }
    phoneIcon(palette, name: name)
}
midnightIcon()
paperIcon()
neonIcon()
pixelIcon()
print("rendered into \(output.path)")
