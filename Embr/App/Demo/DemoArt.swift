#if DEBUG
import UIKit

enum DemoMotif: Sendable {
    case peaks, arena, space, farm, road, dungeon, studio, board, room, canvas
}

struct DemoPalette: Sendable {
    let sky: UInt32
    let horizon: UInt32
    let ground: UInt32
    let accent: UInt32
}

/// A small deterministic generator, so every launch paints the same pictures.
struct DemoRandom {
    private var state: UInt64

    init(seed: String) {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        state = hash
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }

    mutating func unit() -> CGFloat {
        CGFloat(next() % 1_000_000) / 1_000_000
    }

    mutating func range(_ low: CGFloat, _ high: CGFloat) -> CGFloat {
        low + unit() * (high - low)
    }

    mutating func pick<T>(_ items: [T]) -> T {
        items[Int(next() % UInt64(items.count))]
    }
}

/// Procedural pictures standing in for stream frames, thumbnails, box art, avatars and emotes, drawn
/// from a seed so nothing is downloaded and nothing is a real person's or a real game's artwork.
enum DemoArt {
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

    static func image(for url: URL) -> UIImage? {
        let key = url.absoluteString as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return nil }
        let image: UIImage?
        switch parts[0] {
        case "thumb", "vod", "clip":
            let size = Self.size(from: parts.last, fallback: CGSize(width: 440, height: 248))
            image = stream(key: parts[1], size: size, facecam: parts[0] != "vod" || parts[1].hasSuffix("0"))
        case "frame":
            image = stream(key: parts[1], size: CGSize(width: 1280, height: 720), facecam: true)
        case "box":
            let size = Self.size(from: parts.last, fallback: CGSize(width: 285, height: 380))
            image = boxArt(gameID: parts[1], size: size)
        case "avatar":
            image = avatar(login: parts[1], size: 300)
        case "emote":
            let scale = CGFloat(Int(parts.last ?? "1") ?? 1)
            image = emote(name: parts[1], side: 28 * scale)
        case "badge":
            image = badge(set: parts[1], side: 36)
        default:
            image = nil
        }
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    private static func size(from component: String?, fallback: CGSize) -> CGSize {
        let pieces = (component ?? "").split(separator: "x").compactMap { Double($0) }
        guard pieces.count == 2, pieces[0] > 0, pieces[1] > 0 else { return fallback }
        return CGSize(width: pieces[0], height: pieces[1])
    }

    /// The key is a channel login, optionally followed by digits that vary the picture for that
    /// channel's past broadcasts and clips: each number borrows the next category's scenery.
    static func stream(key: String, size: CGSize, facecam: Bool) -> UIImage {
        let login = String(key.reversed().drop { $0.isNumber }.reversed())
        let variant = Int(key.dropFirst(login.count)) ?? 0
        let channel = DemoWorld.channel(login: login)
        let baseIndex = channel.flatMap { owner in DemoWorld.games.firstIndex { $0.id == owner.gameID } } ?? 0
        let game = DemoWorld.games[(baseIndex + variant * 3) % DemoWorld.games.count]
        var random = DemoRandom(seed: "frame-" + key)
        let palette = shifted(game.palette, by: random.range(-0.07, 0.07))
        return render(size) { context in
            drawScene(context, size: size, motif: game.motif, palette: palette, random: &random)
            if hasHUD(game.motif) { drawHUD(context, size: size, palette: palette, random: &random) }
            if facecam { drawFacecam(context, size: size, login: login, palette: palette) }
        }
    }

    /// Channels in one category share its look; a small turn of hue keeps their pictures apart.
    private static func shifted(_ palette: DemoPalette, by amount: CGFloat) -> DemoPalette {
        DemoPalette(
            sky: shifted(palette.sky, by: amount), horizon: shifted(palette.horizon, by: amount),
            ground: shifted(palette.ground, by: amount), accent: shifted(palette.accent, by: amount * 0.5))
    }

    private static func shifted(_ value: UInt32, by amount: CGFloat) -> UInt32 {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb(value).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let turned = UIColor(hue: (hue + amount + 1).truncatingRemainder(dividingBy: 1), saturation: saturation, brightness: brightness, alpha: 1)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
        turned.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (UInt32(red * 255) << 16) | (UInt32(green * 255) << 8) | UInt32(blue * 255)
    }

    static func boxArt(gameID: String, size: CGSize) -> UIImage {
        let game = DemoWorld.game(id: gameID) ?? DemoWorld.games[0]
        var random = DemoRandom(seed: "box-" + gameID)
        return render(size) { context in
            drawScene(context, size: size, motif: game.motif, palette: game.palette, random: &random)
            let shade = [UIColor.black.withAlphaComponent(0).cgColor, UIColor.black.withAlphaComponent(0.78).cgColor]
            fill(context, rect: CGRect(x: 0, y: size.height * 0.45, width: size.width, height: size.height * 0.55), colors: shade)
            let style = NSMutableParagraphStyle()
            style.alignment = .left
            style.lineBreakMode = .byWordWrapping
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size.width * 0.115, weight: .heavy),
                .foregroundColor: UIColor.white,
                .paragraphStyle: style
            ]
            let inset = size.width * 0.09
            let text = game.name.uppercased() as NSString
            let box = CGRect(x: inset, y: size.height * 0.62, width: size.width - inset * 2, height: size.height * 0.34)
            text.draw(with: box, options: [.usesLineFragmentOrigin], attributes: attributes, context: nil)
        }
    }

    static func avatar(login: String, size: CGFloat) -> UIImage {
        var random = DemoRandom(seed: "avatar-" + login)
        let hue = random.unit()
        let first = UIColor(hue: hue, saturation: 0.62, brightness: 0.86, alpha: 1)
        let second = UIColor(hue: (hue + 0.12 + random.range(0, 0.1)).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.55, alpha: 1)
        let name = DemoWorld.channel(login: login)?.name ?? login
        let initial = String(name.prefix(1)).uppercased()
        return render(CGSize(width: size, height: size)) { context in
            fill(context, rect: CGRect(x: 0, y: 0, width: size, height: size), colors: [first.cgColor, second.cgColor], angle: 0.8)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size * 0.5, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.95)
            ]
            let text = initial as NSString
            let measured = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (size - measured.width) / 2, y: (size - measured.height) / 2), withAttributes: attributes)
        }
    }

    static func emote(name: String, side: CGFloat) -> UIImage {
        var random = DemoRandom(seed: "emote-" + name)
        let hue = random.unit()
        let base = UIColor(hue: hue, saturation: 0.55, brightness: 0.98, alpha: 1)
        let edge = UIColor(hue: hue, saturation: 0.75, brightness: 0.7, alpha: 1)
        let mouth = Int(random.next() % 4)
        return render(CGSize(width: side, height: side)) { context in
            let face = CGRect(x: side * 0.05, y: side * 0.05, width: side * 0.9, height: side * 0.9)
            context.setFillColor(edge.cgColor)
            context.fillEllipse(in: face)
            context.setFillColor(base.cgColor)
            context.fillEllipse(in: face.insetBy(dx: side * 0.04, dy: side * 0.04))
            context.setFillColor(UIColor(white: 0.1, alpha: 1).cgColor)
            let eyeY = side * 0.38
            let eye = side * (mouth == 1 ? 0.07 : 0.12)
            context.fillEllipse(in: CGRect(x: side * 0.3, y: eyeY, width: eye, height: eye * (mouth == 3 ? 0.4 : 1.3)))
            context.fillEllipse(in: CGRect(x: side * 0.58, y: eyeY, width: eye, height: eye * (mouth == 3 ? 0.4 : 1.3)))
            context.setStrokeColor(UIColor(white: 0.1, alpha: 1).cgColor)
            context.setLineWidth(side * 0.06)
            context.setLineCap(.round)
            let path = CGMutablePath()
            switch mouth {
            case 0: path.addArc(center: CGPoint(x: side / 2, y: side * 0.55), radius: side * 0.2, startAngle: 0.2, endAngle: .pi - 0.2, clockwise: false)
            case 1:
                context.setFillColor(UIColor(white: 0.1, alpha: 1).cgColor)
                context.fillEllipse(in: CGRect(x: side * 0.4, y: side * 0.62, width: side * 0.2, height: side * 0.2))
            case 2: path.move(to: CGPoint(x: side * 0.36, y: side * 0.7)); path.addLine(to: CGPoint(x: side * 0.64, y: side * 0.7))
            default: path.addArc(center: CGPoint(x: side / 2, y: side * 0.78), radius: side * 0.2, startAngle: .pi + 0.3, endAngle: -0.3, clockwise: false)
            }
            context.addPath(path)
            context.strokePath()
        }
    }

    static func badge(set: String, side: CGFloat) -> UIImage {
        let color: UInt32
        switch set {
        case "moderator": color = 0x2fb344
        case "subscriber": color = 0x8a5cf5
        case "vip": color = 0xe0529c
        case "broadcaster": color = 0xe5484d
        default: color = 0x3b82f6
        }
        return render(CGSize(width: side, height: side)) { context in
            context.setFillColor(rgb(color).cgColor)
            let inset = side * 0.08
            let path = UIBezierPath(roundedRect: CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2), cornerRadius: side * 0.22)
            context.addPath(path.cgPath)
            context.fillPath()
            context.setFillColor(UIColor.white.cgColor)
            let center = CGPoint(x: side / 2, y: side / 2)
            if set == "subscriber" || set == "vip" {
                context.addPath(star(center: center, radius: side * 0.28, points: set == "vip" ? 4 : 5))
                context.fillPath()
            } else if set == "moderator" {
                context.setStrokeColor(UIColor.white.cgColor)
                context.setLineCap(.round)
                context.setLineWidth(side * 0.11)
                context.move(to: CGPoint(x: side * 0.3, y: side * 0.7))
                context.addLine(to: CGPoint(x: side * 0.7, y: side * 0.3))
                context.strokePath()
                context.setLineWidth(side * 0.08)
                context.move(to: CGPoint(x: side * 0.28, y: side * 0.5))
                context.addLine(to: CGPoint(x: side * 0.5, y: side * 0.72))
                context.strokePath()
            } else {
                context.fillEllipse(in: CGRect(x: side * 0.3, y: side * 0.3, width: side * 0.4, height: side * 0.4))
            }
        }
    }

    private static func star(center: CGPoint, radius: CGFloat, points: Int) -> CGPath {
        let path = CGMutablePath()
        for index in 0..<(points * 2) {
            let angle = CGFloat(index) * .pi / CGFloat(points) - .pi / 2
            let length = index % 2 == 0 ? radius : radius * 0.45
            let point = CGPoint(x: center.x + cos(angle) * length, y: center.y + sin(angle) * length)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private static func render(_ size: CGSize, draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
    }

    private static func rgb(_ value: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: alpha
        )
    }

    private static func mix(_ first: UInt32, _ second: UInt32, _ amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        rgb(first).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        rgb(second).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * amount, green: g1 + (g2 - g1) * amount, blue: b1 + (b2 - b1) * amount, alpha: 1)
    }

    private static func fill(_ context: CGContext, rect: CGRect, colors: [CGColor], angle: CGFloat = 0) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil) else { return }
        context.saveGState()
        context.clip(to: rect)
        let start = CGPoint(x: rect.midX - rect.width * angle / 2, y: rect.minY)
        let end = CGPoint(x: rect.midX + rect.width * angle / 2, y: rect.maxY)
        context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }

    private static func glow(_ context: CGContext, center: CGPoint, radius: CGFloat, color: UIColor) {
        let colors = [color.withAlphaComponent(0.95).cgColor, color.withAlphaComponent(0).cgColor]
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil) else { return }
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    private static func hasHUD(_ motif: DemoMotif) -> Bool {
        switch motif {
        case .peaks, .arena, .space, .road, .dungeon: return true
        default: return false
        }
    }

    private static func drawScene(_ context: CGContext, size: CGSize, motif: DemoMotif, palette: DemoPalette, random: inout DemoRandom) {
        let bounds = CGRect(origin: .zero, size: size)
        switch motif {
        case .peaks: drawPeaks(context, bounds: bounds, palette: palette, random: &random)
        case .arena: drawArena(context, bounds: bounds, palette: palette, random: &random)
        case .space: drawSpace(context, bounds: bounds, palette: palette, random: &random)
        case .farm: drawFarm(context, bounds: bounds, palette: palette, random: &random)
        case .road: drawRoad(context, bounds: bounds, palette: palette, random: &random)
        case .dungeon: drawDungeon(context, bounds: bounds, palette: palette, random: &random)
        case .studio: drawStudio(context, bounds: bounds, palette: palette, random: &random)
        case .board: drawBoard(context, bounds: bounds, palette: palette, random: &random)
        case .room: drawRoom(context, bounds: bounds, palette: palette, random: &random)
        case .canvas: drawCanvas(context, bounds: bounds, palette: palette, random: &random)
        }
    }

    private static func ridge(_ context: CGContext, bounds: CGRect, base: CGFloat, amplitude: CGFloat, color: UIColor, random: inout DemoRandom) {
        let phaseA = random.range(0, 6), phaseB = random.range(0, 6)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: bounds.height))
        var x: CGFloat = 0
        while x <= bounds.width + 4 {
            let t = x / bounds.width
            let wave = sin(t * 5 + phaseA) * 0.6 + sin(t * 13 + phaseB) * 0.3 + sin(t * 29 + phaseA) * 0.1
            path.addLine(to: CGPoint(x: x, y: base - wave * amplitude))
            x += 4
        }
        path.addLine(to: CGPoint(x: bounds.width, y: bounds.height))
        path.closeSubpath()
        context.setFillColor(color.cgColor)
        context.addPath(path)
        context.fillPath()
    }

    private static func drawPeaks(_ context: CGContext, bounds: CGRect, palette: DemoPalette, random: inout DemoRandom) {
        fill(context, rect: bounds, colors: [rgb(palette.sky).cgColor, rgb(palette.horizon).cgColor])
        let sun = CGPoint(x: bounds.width * random.range(0.2, 0.8), y: bounds.height * random.range(0.28, 0.42))
        glow(context, center: sun, radius: bounds.height * 0.45, color: rgb(palette.accent, alpha: 0.7))
        context.setFillColor(rgb(palette.accent).cgColor)
        context.fillEllipse(in: CGRect(x: sun.x - bounds.height * 0.07, y: sun.y - bounds.height * 0.07, width: bounds.height * 0.14, height: bounds.height * 0.14))
        for layer in 0..<4 {
            let amount = CGFloat(layer) / 3
            ridge(
                context, bounds: bounds, base: bounds.height * (0.5 + 0.12 * CGFloat(layer)),
                amplitude: bounds.height * (0.16 - 0.025 * CGFloat(layer)),
                color: mix(palette.horizon, palette.ground, 0.25 + amount * 0.75), random: &random
            )
        }
        context.setFillColor(rgb(palette.ground, alpha: 1).cgColor)
        for _ in 0..<Int(bounds.width / 38) {
            let x = random.range(0, bounds.width)
            let base = bounds.height * random.range(0.9, 1.02)
            let height = bounds.height * random.range(0.12, 0.26)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: base - height))
            path.addLine(to: CGPoint(x: x - height * 0.22, y: base))
            path.addLine(to: CGPoint(x: x + height * 0.22, y: base))
            path.closeSubpath()
            context.addPath(path)
            context.fillPath()
        }
    }

    private static func drawArena(_ context: CGContext, bounds: CGRect, palette: DemoPalette, random: inout DemoRandom) {
        fill(context, rect: bounds, colors: [rgb(palette.sky).cgColor, rgb(palette.horizon).cgColor, rgb(palette.ground).cgColor])
        let horizon = bounds.height * 0.42
        let vanishing = CGPoint(x: bounds.width / 2, y: horizon)
        context.setStrokeColor(rgb(palette.accent, alpha: 0.38).cgColor)
        context.setLineWidth(max(1, bounds.height * 0.004))
        for index in -14...14 {
            context.move(to: vanishing)
            context.addLine(to: CGPoint(x: bounds.width / 2 + CGFloat(index) * bounds.width * 0.14, y: bounds.height))
        }
        var y = horizon
        var step = bounds.height * 0.012
        while y < bounds.height {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: bounds.width, y: y))
            y += step
            step *= 1.28
        }
        context.strokePath()
        for _ in 0..<5 {
            let x = random.range(0.1, 0.9) * bounds.width
            let beam = CGRect(x: x, y: 0, width: bounds.width * random.range(0.01, 0.025), height: horizon + bounds.height * 0.1)
            fill(context, rect: beam, colors: [rgb(palette.accent, alpha: 0).cgColor, rgb(palette.accent, alpha: 0.55).cgColor])
        }
        for _ in 0..<7 {
            let point = CGPoint(x: random.range(0.08, 0.92) * bounds.width, y: random.range(0.55, 0.92) * bounds.height)
            let radius = bounds.height * random.range(0.03, 0.06)
            glow(context, center: point, radius: radius * 3, color: rgb(palette.accent, alpha: 0.6))
            context.setFillColor(mix(palette.sky, 0xffffff, 0.8).cgColor)
            context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            context.setFillColor(rgb(palette.accent).cgColor)
            context.fillEllipse(in: CGRect(x: point.x - radius * 0.5, y: point.y - radius * 0.5, width: radius, height: radius))
        }
    }

    private static func drawSpace(_ context: CGContext, bounds: CGRect, palette: DemoPalette, random: inout DemoRandom) {
        fill(context, rect: bounds, colors: [rgb(palette.sky).cgColor, rgb(palette.horizon).cgColor])
        context.setFillColor(UIColor.white.cgColor)
        for _ in 0..<Int(bounds.width * bounds.height / 2600) {
            let side = random.range(0.6, 2.2) * max(1, bounds.height / 360)
            context.setAlpha(random.range(0.3, 1))
            context.fillEllipse(in: CGRect(x: random.range(0, bounds.width), y: random.range(0, bounds.height), width: side, height: side))
        }
        context.setAlpha(1)
        let planet = CGPoint(x: bounds.width * random.range(0.62, 0.85), y: bounds.height * random.range(0.5, 0.7))
        let radius = bounds.height * 0.34
        glow(context, center: planet, radius: radius * 1.9, color: rgb(palette.accent, alpha: 0.4))
        context.saveGState()
        context.addEllipse(in: CGRect(x: planet.x - radius, y: planet.y - radius, width: radius * 2, height: radius * 2))
        context.clip()
        fill(context, rect: CGRect(x: planet.x - radius, y: planet.y - radius, width: radius * 2, height: radius * 2), colors: [rgb(palette.accent).cgColor, rgb(palette.ground).cgColor], angle: 0.9)
        context.restoreGState()
        context.setStrokeColor(rgb(palette.accent, alpha: 0.6).cgColor)
        context.setLineWidth(max(2, bounds.height * 0.012))
        context.strokeEllipse(in: CGRect(x: planet.x - radius * 1.6, y: planet.y - radius * 0.32, width: radius * 3.2, height: radius * 0.64))
        let ship = CGPoint(x: bounds.width * 0.3, y: bounds.height * 0.55)
        let length = bounds.height * 0.14
        glow(context, center: CGPoint(x: ship.x - length, y: ship.y), radius: length, color: rgb(palette.accent, alpha: 0.9))
        let path = CGMutablePath()
        path.move(to: CGPoint(x: ship.x + length, y: ship.y))
        path.addLine(to: CGPoint(x: ship.x - length * 0.6, y: ship.y - length * 0.45))
        path.addLine(to: CGPoint(x: ship.x - length * 0.3, y: ship.y))
        path.addLine(to: CGPoint(x: ship.x - length * 0.6, y: ship.y + length * 0.45))
        path.closeSubpath()
        context.setFillColor(mix(0xd8e2f2, palette.sky, 0.1).cgColor)
        context.addPath(path)
        context.fillPath()
    }

    private static func drawFarm(_ context: CGContext, bounds: CGRect, palette: DemoPalette, random: inout DemoRandom) {
        fill(context, rect: bounds, colors: [rgb(palette.sky).cgColor, rgb(palette.horizon).cgColor])
        context.setFillColor(UIColor.white.withAlphaComponent(0.7).cgColor)
        for _ in 0..<4 {
            let center = CGPoint(x: random.range(0, bounds.width), y: random.range(0.08, 0.3) * bounds.height)
            let width = bounds.width * random.range(0.12, 0.22)
            context.fillEllipse(in: CGRect(x: center.x, y: center.y, width: width, height: width * 0.32))
            context.fillEllipse(in: CGRect(x: center.x + width * 0.2, y: center.y - width * 0.1, width: width * 0.5, height: width * 0.3))
        }
        ridge(context, bounds: bounds, base: bounds.height * 0.55, amplitude: bounds.height * 0.07, color: mix(palette.horizon, palette.ground, 0.4), random: &random)
        ridge(context, bounds: bounds, base: bounds.height * 0.68, amplitude: bounds.height * 0.05, color: mix(palette.horizon, palette.ground, 0.75), random: &random)
        let barn = CGRect(x: bounds.width * random.range(0.1, 0.55), y: bounds.height * 0.42, width: bounds.width * 0.16, height: bounds.height * 0.16)
        context.setFillColor(rgb(palette.accent).cgColor)
        context.fill(barn)
        let roof = CGMutablePath()
        roof.move(to: CGPoint(x: barn.minX - barn.width * 0.08, y: barn.minY))
        roof.addLine(to: CGPoint(x: barn.midX, y: barn.minY - barn.height * 0.5))
        roof.addLine(to: CGPoint(x: barn.maxX + barn.width * 0.08, y: barn.minY))
        roof.closeSubpath()
        context.setFillColor(mix(palette.accent, 0x000000, 0.4).cgColor)
        context.addPath(roof)
        context.fillPath()
        context.setFillColor(rgb(palette.ground).cgColor)
        context.fill(CGRect(x: 0, y: bounds.height * 0.78, width: bounds.width, height: bounds.height * 0.22))
        context.setStrokeColor(mix(palette.ground, 0x000000, 0.35).cgColor)
        context.setLineWidth(max(2, bounds.height * 0.014))
        for row in 0..<6 {
            let y = bounds.height * (0.8 + CGFloat(row) * 0.035)
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: bounds.width, y: y))
        }
        context.strokePath()
        context.setFillColor(UIColor(red: 0.95, green: 0.78, blue: 0.35, alpha: 1).cgColor)
        for _ in 0..<Int(bounds.width / 18) {
            let radius = bounds.height * 0.012
            context.fillEllipse(in: CGRect(x: random.range(0, bounds.width), y: bounds.height * random.range(0.8, 0.98), width: radius * 2, height: radius * 2))
        }
    }

    private static func drawRoad(_ context: CGContext, bounds: CGRect, palette: DemoPalette, random: inout DemoRandom) {
        fill(context, rect: bounds, colors: [rgb(palette.sky).cgColor, rgb(palette.horizon).cgColor])
        let horizon = bounds.height * 0.46
        glow(context, center: CGPoint(x: bounds.width * 0.7, y: horizon), radius: bounds.height * 0.5, color: rgb(palette.accent, alpha: 0.6))
        ridge(context, bounds: bounds, base: horizon, amplitude: bounds.height * 0.1, color: mix(palette.horizon, palette.ground, 0.6), random: &random)
        context.setFillColor(rgb(palette.ground).cgColor)
        context.fill(CGRect(x: 0, y: horizon, width: bounds.width, height: bounds.height - horizon))
        let road = CGMutablePath()
        road.move(to: CGPoint(x: bounds.width * 0.47, y: horizon))
        road.addLine(to: CGPoint(x: bounds.width * 0.53, y: horizon))
        road.addLine(to: CGPoint(x: bounds.width * 1.0, y: bounds.height))
        road.addLine(to: CGPoint(x: 0, y: bounds.height))
        road.closeSubpath()
        context.setFillColor(UIColor(white: 0.16, alpha: 1).cgColor)
        context.addPath(road)
        context.fillPath()
        context.setFillColor(UIColor(white: 0.95, alpha: 0.9).cgColor)
        var y = horizon + bounds.height * 0.02
        var length = bounds.height * 0.012
        while y < bounds.height {
            let t = (y - horizon) / (bounds.height - horizon)
            let width = max(1.5, bounds.width * 0.012 * (0.3 + t * 2.2))
            context.fill(CGRect(x: bounds.width / 2 - width / 2, y: y, width: width, height: length))
            y += length * 2.1
            length *= 1.22
        }
        let car = CGRect(x: bounds.width * 0.4, y: bounds.height * 0.76, width: bounds.width * 0.2, height: bounds.height * 0.14)
        context.setFillColor(UIColor(white: 0.07, alpha: 1).cgColor)
        context.addPath(UIBezierPath(roundedRect: car, cornerRadius: car.height * 0.3).cgPath)
        context.fillPath()
        context.setFillColor(rgb(palette.accent).cgColor)
        context.fill(CGRect(x: car.minX + car.width * 0.08, y: car.midY, width: car.width * 0.18, height: car.height * 0.14))
        context.fill(CGRect(x: car.maxX - car.width * 0.26, y: car.midY, width: car.width * 0.18, height: car.height * 0.14))
    }

    private static func drawDungeon(_ context: CGContext, bounds: CGRect, palette: DemoPalette, random: inout DemoRandom) {
        let tile = max(10, (bounds.height / 15).rounded())
        let columns = Int(bounds.width / tile) + 1
        let rows = Int(bounds.height / tile) + 1
        for row in 0..<rows {
            for column in 0..<columns {
                let wall = row < 2 || row > rows - 3 || column < 1 || column > columns - 2 || random.unit() < 0.06
                let shade = random.range(0, 0.25)
                let color = wall ? mix(palette.sky, palette.horizon, shade) : mix(palette.ground, palette.horizon, shade)
                context.setFillColor(color.cgColor)
                context.fill(CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile - 1, height: tile - 1))
            }
        }
        for _ in 0..<3 {
            let point = CGPoint(x: tile * CGFloat(Int(random.range(2, CGFloat(columns - 2)))), y: tile * CGFloat(Int(random.range(2, CGFloat(rows - 2)))))
            glow(context, center: point, radius: tile * 4, color: rgb(palette.accent, alpha: 0.55))
            context.setFillColor(rgb(palette.accent).cgColor)
            context.fill(CGRect(x: point.x - tile * 0.2, y: point.y - tile * 0.2, width: tile * 0.4, height: tile * 0.4))
        }
        let hero = CGPoint(x: tile * CGFloat(columns / 2), y: tile * CGFloat(rows / 2))
        context.setFillColor(rgb(palette.accent).cgColor)
        context.fill(CGRect(x: hero.x, y: hero.y, width: tile, height: tile * 1.4))
        context.setFillColor(mix(0xf4d6b0, palette.accent, 0.1).cgColor)
        context.fill(CGRect(x: hero.x + tile * 0.15, y: hero.y - tile * 0.5, width: tile * 0.7, height: tile * 0.6))
        for _ in 0..<4 {
            context.setFillColor(mix(0x4ade80, palette.sky, 0.2).cgColor)
            context.fill(CGRect(x: tile * CGFloat(Int(random.range(2, CGFloat(columns - 2)))), y: tile * CGFloat(Int(random.range(3, CGFloat(rows - 3)))), width: tile, height: tile * 0.8))
        }
    }

    private static func drawStudio(_ context: CGContext, bounds: CGRect, palette: DemoPalette, random: inout DemoRandom) {
        fill(context, rect: bounds, colors: [rgb(palette.sky).cgColor, rgb(palette.horizon).cgColor])
        let center = CGPoint(x: bounds.width * 0.5, y: bounds.height * 0.42)
        let radius = min(bounds.width, bounds.height) * 0.3
        glow(context, center: center, radius: radius * 2.4, color: rgb(palette.accent, alpha: 0.5))
        context.setFillColor(UIColor(white: 0.05, alpha: 1).cgColor)
        context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.setStrokeColor(UIColor(white: 0.25, alpha: 1).cgColor)
        context.setLineWidth(1)
        var ring = radius * 0.3
        while ring < radius {
            context.strokeEllipse(in: CGRect(x: center.x - ring, y: center.y - ring, width: ring * 2, height: ring * 2))
            ring += max(3, radius * 0.07)
        }
        context.setFillColor(rgb(palette.accent).cgColor)
        context.fillEllipse(in: CGRect(x: center.x - radius * 0.22, y: center.y - radius * 0.22, width: radius * 0.44, height: radius * 0.44))
        let barWidth = max(3, bounds.width / 64)
        var x = barWidth
        while x < bounds.width {
            let height = bounds.height * random.range(0.04, 0.2)
            context.setFillColor(rgb(palette.accent, alpha: random.range(0.5, 1)).cgColor)
            context.fill(CGRect(x: x, y: bounds.height - height - bounds.height * 0.04, width: barWidth * 0.7, height: height))
            x += barWidth * 1.4
        }
    }

    private static func drawBoard(_ context: CGContext, bounds: CGRect, palette: DemoPalette, random: inout DemoRandom) {
        fill(context, rect: bounds, colors: [rgb(palette.sky).cgColor, rgb(palette.horizon).cgColor])
        let side = min(bounds.width, bounds.height) * 0.86
        let origin = CGPoint(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2)
        let cell = side / 8
        for row in 0..<8 {
            for column in 0..<8 {
                context.setFillColor((row + column) % 2 == 0 ? rgb(palette.ground).cgColor : mix(palette.ground, 0x000000, 0.45).cgColor)
                context.fill(CGRect(x: origin.x + CGFloat(column) * cell, y: origin.y + CGFloat(row) * cell, width: cell, height: cell))
            }
        }
        for _ in 0..<12 {
            let column = CGFloat(Int(random.range(0, 8))), row = CGFloat(Int(random.range(0, 8)))
            let light = random.unit() < 0.5
            let center = CGPoint(x: origin.x + (column + 0.5) * cell, y: origin.y + (row + 0.5) * cell)
            context.setFillColor((light ? UIColor(white: 0.94, alpha: 1) : UIColor(white: 0.1, alpha: 1)).cgColor)
            context.fillEllipse(in: CGRect(x: center.x - cell * 0.26, y: center.y - cell * 0.18, width: cell * 0.52, height: cell * 0.5))
            context.fillEllipse(in: CGRect(x: center.x - cell * 0.14, y: center.y - cell * 0.38, width: cell * 0.28, height: cell * 0.28))
        }
        context.setStrokeColor(rgb(palette.accent).cgColor)
        context.setLineWidth(max(2, cell * 0.06))
        context.stroke(CGRect(x: origin.x + cell * 3, y: origin.y + cell * 4, width: cell, height: cell))
    }

    private static func drawRoom(_ context: CGContext, bounds: CGRect, palette: DemoPalette, random: inout DemoRandom) {
        fill(context, rect: bounds, colors: [rgb(palette.sky).cgColor, rgb(palette.horizon).cgColor, rgb(palette.ground).cgColor])
        for _ in 0..<26 {
            let radius = bounds.height * random.range(0.02, 0.1)
            let point = CGPoint(x: random.range(0, bounds.width), y: random.range(0, bounds.height * 0.7))
            context.setFillColor(mix(palette.accent, 0xffffff, random.range(0, 0.6)).withAlphaComponent(random.range(0.12, 0.35)).cgColor)
            context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        }
        context.setFillColor(mix(palette.ground, 0x000000, 0.5).cgColor)
        context.fill(CGRect(x: 0, y: bounds.height * 0.78, width: bounds.width, height: bounds.height * 0.22))
        let monitor = CGRect(x: bounds.width * 0.58, y: bounds.height * 0.5, width: bounds.width * 0.26, height: bounds.height * 0.22)
        context.setFillColor(UIColor(white: 0.08, alpha: 1).cgColor)
        context.addPath(UIBezierPath(roundedRect: monitor, cornerRadius: 4).cgPath)
        context.fillPath()
        glow(context, center: CGPoint(x: monitor.midX, y: monitor.midY), radius: monitor.width, color: rgb(palette.accent, alpha: 0.35))
        let lamp = CGPoint(x: bounds.width * 0.14, y: bounds.height * 0.34)
        glow(context, center: lamp, radius: bounds.height * 0.5, color: UIColor(red: 1, green: 0.8, blue: 0.5, alpha: 0.55))
    }

    private static func drawCanvas(_ context: CGContext, bounds: CGRect, palette: DemoPalette, random: inout DemoRandom) {
        fill(context, rect: bounds, colors: [mix(palette.sky, 0xffffff, 0.82).cgColor, mix(palette.horizon, 0xffffff, 0.75).cgColor])
        for _ in 0..<5 {
            let point = CGPoint(x: random.range(0, bounds.width), y: random.range(0, bounds.height))
            glow(context, center: point, radius: bounds.height * random.range(0.25, 0.5), color: mix(palette.accent, palette.ground, random.unit()).withAlphaComponent(0.5))
        }
        context.setLineCap(.round)
        for _ in 0..<9 {
            context.setStrokeColor(mix(palette.accent, palette.ground, random.unit()).withAlphaComponent(0.85).cgColor)
            context.setLineWidth(bounds.height * random.range(0.03, 0.09))
            let start = CGPoint(x: random.range(0.05, 0.95) * bounds.width, y: random.range(0.1, 0.9) * bounds.height)
            context.move(to: start)
            context.addQuadCurve(to: CGPoint(x: start.x + random.range(-0.3, 0.3) * bounds.width, y: start.y + random.range(-0.3, 0.3) * bounds.height),
                                 control: CGPoint(x: start.x + random.range(-0.25, 0.25) * bounds.width, y: start.y + random.range(-0.25, 0.25) * bounds.height))
            context.strokePath()
        }
    }

    private static func drawHUD(_ context: CGContext, size: CGSize, palette: DemoPalette, random: inout DemoRandom) {
        let unit = size.height / 360
        let margin = 14 * unit
        let bar = CGRect(x: margin, y: margin, width: 150 * unit, height: 12 * unit)
        context.setFillColor(UIColor.black.withAlphaComponent(0.5).cgColor)
        context.addPath(UIBezierPath(roundedRect: bar.insetBy(dx: -3 * unit, dy: -3 * unit), cornerRadius: 8 * unit).cgPath)
        context.fillPath()
        context.setFillColor(rgb(palette.accent).cgColor)
        context.addPath(UIBezierPath(roundedRect: CGRect(x: bar.minX, y: bar.minY, width: bar.width * random.range(0.45, 0.9), height: bar.height), cornerRadius: 6 * unit).cgPath)
        context.fillPath()
        let score = CGRect(x: size.width - margin - 82 * unit, y: margin - 3 * unit, width: 82 * unit, height: 24 * unit)
        context.setFillColor(UIColor.black.withAlphaComponent(0.5).cgColor)
        context.addPath(UIBezierPath(roundedRect: score, cornerRadius: 12 * unit).cgPath)
        context.fillPath()
        context.setFillColor(rgb(palette.accent).cgColor)
        for index in 0..<5 {
            context.fill(CGRect(x: score.minX + 14 * unit + CGFloat(index) * 12 * unit, y: score.midY - 4 * unit, width: 8 * unit, height: 8 * unit))
        }
        let map = CGRect(x: size.width - margin - 74 * unit, y: size.height - margin - 74 * unit, width: 74 * unit, height: 74 * unit)
        context.setFillColor(UIColor.black.withAlphaComponent(0.45).cgColor)
        context.fillEllipse(in: map)
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.6).cgColor)
        context.setLineWidth(max(1, 1.5 * unit))
        context.strokeEllipse(in: map)
        context.setFillColor(rgb(palette.accent).cgColor)
        context.fillEllipse(in: CGRect(x: map.midX - 4 * unit, y: map.midY - 4 * unit, width: 8 * unit, height: 8 * unit))
        context.setFillColor(UIColor.white.cgColor)
        for _ in 0..<3 {
            let angle = random.range(0, .pi * 2)
            let distance = random.range(14, 30) * unit
            context.fillEllipse(in: CGRect(x: map.midX + cos(angle) * distance - 2 * unit, y: map.midY + sin(angle) * distance - 2 * unit, width: 4 * unit, height: 4 * unit))
        }
    }

    private static func drawFacecam(_ context: CGContext, size: CGSize, login: String, palette: DemoPalette) {
        var random = DemoRandom(seed: "cam-" + login)
        let unit = size.height / 360
        let frame = CGRect(x: 14 * unit, y: size.height - 14 * unit - 96 * unit, width: 128 * unit, height: 96 * unit)
        context.saveGState()
        context.addPath(UIBezierPath(roundedRect: frame, cornerRadius: 10 * unit).cgPath)
        context.clip()
        let wall = UIColor(hue: random.unit(), saturation: 0.3, brightness: 0.5, alpha: 1)
        fill(context, rect: frame, colors: [wall.cgColor, mix(palette.sky, 0x000000, 0.3).cgColor])
        let skin = random.pick([0xf1c9a5, 0xd9a273, 0xa86f48, 0x7b4a2d, 0xf6d9c0] as [UInt32])
        let shirt = UIColor(hue: random.unit(), saturation: 0.55, brightness: 0.6, alpha: 1)
        context.setFillColor(shirt.cgColor)
        context.fillEllipse(in: CGRect(x: frame.midX - 46 * unit, y: frame.maxY - 30 * unit, width: 92 * unit, height: 80 * unit))
        context.setFillColor(rgb(skin).cgColor)
        context.fillEllipse(in: CGRect(x: frame.midX - 21 * unit, y: frame.minY + 18 * unit, width: 42 * unit, height: 50 * unit))
        context.setFillColor(mix(0x2b1d14, 0xd9b36a, random.unit()).cgColor)
        context.fill(CGRect(x: frame.midX - 22 * unit, y: frame.minY + 15 * unit, width: 44 * unit, height: 14 * unit))
        context.restoreGState()
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.55).cgColor)
        context.setLineWidth(max(1, 1.5 * unit))
        context.addPath(UIBezierPath(roundedRect: frame, cornerRadius: 10 * unit).cgPath)
        context.strokePath()
    }
}
#endif
