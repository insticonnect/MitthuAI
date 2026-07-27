import AppKit

/// MitthuAI's brand mark — the parrot ("mitthu") badge used on mitthuai.com.
///
/// The artwork is declared once, in SVG user space (a 1024×1024 box whose y
/// grows downward), and rendered two ways so every surface stays in sync:
///
///   * `svgMark` — inline SVG for the dashboard header.
///   * `image(size:)` / `menuBarImage(height:)` — NSImages for the menu bar
///     icon, the popover header and the app icon (Tools/MakeIcon.swift).
///
/// Edit the geometry below and all of them move together.
enum BrandLogo {

    // MARK: - Brand values

    /// Nav background the wordmark sits on (matches the site and the dashboard).
    static let inkHex: UInt32 = 0x0E0F13
    /// The wordmark is always white, per the site.
    static let wordmarkHex: UInt32 = 0xFFFFFF
    /// Wordmark typeface. The bundled face comes first, then a system-wide
    /// install of the real thing, then the fallbacks the site itself uses.
    static let wordmarkFamily = "MitthuAI Wordmark"
    /// PostScript name, for NSFont/Font.custom lookups. Registered from
    /// Resources/Fonts via Info.plist's ATSApplicationFontsPath.
    static let wordmarkFontName = "MitthuAIWordmark-Bold"
    static var wordmarkCSSStack: String {
        #""\#(wordmarkFamily)", "Plus Jakarta Sans", ui-sans-serif, system-ui, -apple-system, "SF Pro Text", Helvetica, Arial, sans-serif"#
    }
    /// The site sets the wordmark at 20px.
    static let wordmarkSize: CGFloat = 20

    /// Plus Jakarta Sans Bold, subset to the wordmark's glyphs and renamed to
    /// mark it as a modification — SIL Open Font License 1.1, full text in
    /// Resources/Fonts/OFL.txt. Inlined as WOFF2 so the dashboard renders the
    /// real wordmark with no network and no font install.
    static let wordmarkWoff2Base64 = """
        d09GMgABAAAAAAT0AA8AAAAACrAAAASZAAISLQAAAAAAAAAAAAAAAAAAAAAAAAAAGhwbgUgccgZgP1NUQVREAFwRCAqEKIMgATYC\
        JAMwCxoABCAFiEIHIBsJCSieA+7OIiyapohxygIpYlyMG+PhvzV+983MLurefkQ9mVcOJdHVIqWaZ4nM3+vUp9gpSGX4ITJwCEBA\
        pu+TvkoU4C1rgdfA1PIIyFtvz5Vocrdf7pnkgXFCJSWn7f9/r+p/yaY1cN0MC+mYZDk3c1jOs9gaOgctsgCOLmw/fyrV6/UChkpQ\
        c6rZPWO6MIcjjNLK/tP/pwl0ByRJaIROugiBrsZziFpfVtMCq06yJAyrFKhVIE6IWhiWIRCKpLPQWbKdGTtporUqVf3Hq/pZXB7R\
        6qwRZa5DyMhKSq0LYSk0i3Hdrku85Q1o1nSVIohd19TSVWwr7FJ2FLZIm6oLFh16EvNBVUBDKxWjsaRV6fqwdCuqA8C2wSWxG5Kj\
        HGpZ+LN0dHU9nDGaUavqWND0DgFAQBqd/mI00yZk+neZ8T/gvKwQysSxYYMUIxS9URBd0hsgCym6gwAJGf2ZBPoz2wz01FnSGq1Q\
        pVoq4yukXEF+uf6ut+uVeq0SC+MeteqF0B0MBnrhNu6je2eQIomQSbk4ZKRKnewcS70HD5LDq1o/tdoZJzz9ZrcTjEq3rWjpZroY\
        pulW1NVDtMyYuzYbBFrykh9LUx+/ZiZfvpS65pvz9+iJO7OQMqq7Kcage9/EK4rqGmD5FkV36erG3StU1+XNMPOkFQj7LlO3dGPu\
        ri3dXxhJFtww5MGL/oFld8qWlS1ti768Gxg/Z+HnjOs0cp/u2fzsoJYIFTf2V33hiU0H8tYcOPF3vK5m27416/c9qIPcv4MF61Cb\
        Iyunx+nsye0bzI9fWBEzesdCfD7kjh5EJ3qmBqdgzvCzwdX0CELPvz6DTn6ZnDp46LBx+O/2CYNoacyNyFOn/91W7fTa+OLawaLY\
        c+loonD1/Q8FzsW02eHAToxPQDvRErS6PYaAmcDzTP9/IpD6zjgVY+voX53zd1nkn/BuLn0LAN+n87KAqX/ywkwLrQSCK9qVrwLz\
        fxGZewne0D3dgOXpjm4xSAXaXZFGyLXYMfgBcx5tRpyEgakRHObBZRS6G86ss8SKZIuBsSrZCn0AAUnRB7IBNkIxUOp2q7d7M/D7\
        PGUSpQvewmoCwtgwQ9I5JkI2NSxQTI8OaCyNoe0WhB4xMm5CTwvTh+3eRWR9MKHunvseRpck6SYceb27rnnqDpUQxSis/Mc7fvr4\
        g2y8irudDJ3A08izhmJYxH4alUxBIA62TgVpoYno2CDIoLOtwgpgaQgW0owVpoPsNZifiEcghQyEAtOgTHKJN4kIXRYrK5kK487A\
        seBhIVYEFoAR+0WIrCTMC/FAU9SyReNjFqqEtMM0ghCWJqAIFiTg80MhQ6/IXECRthEX2lBh4U1MWcJ1L7tsMgmBLWu6bjYWmSyc\
        bHq1UKg6U8aQIduawZmZvcWIGMW4Bql4ojCdSIAYwgQiDUKO61qzSjWQepGMWf7dGh6SPlc+sWMH2fBoECYEZa18FZCZaK0wVkgq\
        bsE22rqMyktZehfTjphAJbV4LCJpv+XSUB1/WQcjCJ1FPA2yHM7LMqt6ZWq0Ey90qxLBbl+m6ZKhWCcTUM8lqwEAAAA=
        """

    /// The @font-face rule that pairs with `wordmarkCSSStack`.
    static var wordmarkFontFace: String {
        #"@font-face { font-family: "\#(wordmarkFamily)"; font-style: normal; font-weight: 700; src: url(data:font/woff2;base64,\#(wordmarkWoff2Base64)) format("woff2"); }"#
    }

    static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
                green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                blue: CGFloat(hex & 0xFF) / 255.0, alpha: 1)
    }

    // MARK: - Geometry

    static let canvas: CGFloat = 1024

    private struct Disc {
        let cx: CGFloat, cy: CGFloat, r: CGFloat
    }

    private enum Fill {
        case solid(UInt32)
        /// Top-to-bottom gradient, in SVG space.
        case gradient(UInt32, UInt32)
    }

    private struct Element {
        var d: String = ""
        var discs: [Disc] = []
        var fill: Fill
        /// Even-odd winding, so `discs` punch holes instead of filling in.
        var evenOdd: Bool = false
    }

    /// The orange badge everything else sits on.
    private static let badge = Element(discs: [Disc(cx: 512, cy: 512, r: 470)],
                                       fill: .gradient(0xFF7A2B, 0xE8431A))

    /// Parrot on top of the badge: wing, face patch, beak, eye.
    private static let features: [Element] = [
        Element(d: "M244 424 C158 556 152 726 268 848 C348 926 476 944 648 880 C474 796 340 634 244 424 Z",
                fill: .solid(0xFF9A2B)),
        Element(d: "M534 196 C652 196 726 288 726 400 C726 520 652 592 540 592 C424 592 356 512 356 396 C356 282 420 196 534 196 Z",
                fill: .solid(0xFFFFFF)),
        Element(d: "M452 470 C556 436 704 462 800 540 C726 668 604 722 500 690 C438 630 428 540 452 470 Z",
                fill: .solid(0x1C1C1E)),
        Element(d: "M556 356 C704 330 848 396 900 506 C914 596 862 674 780 706 C806 598 736 506 620 462 C578 440 556 400 556 356 Z",
                fill: .solid(0xEFE3CE)),
        Element(discs: [Disc(cx: 548, cy: 342, r: 64)], fill: .solid(0xF5A623)),
        Element(discs: [Disc(cx: 548, cy: 342, r: 31)], fill: .solid(0x17171A)),
        Element(discs: [Disc(cx: 563, cy: 325, r: 12)], fill: .solid(0xFFFFFF))
    ]

    /// Single-colour version for the menu bar: the same parrot reduced to a
    /// head-and-hooked-beak silhouette with the eye knocked out, because the
    /// full badge turns to mush at 18pt.
    private static let mono = Element(
        d: """
        M350 130 C470 130 546 158 566 202 C700 236 830 330 858 452 \
        C878 560 800 664 706 714 C686 668 660 592 618 540 \
        C590 506 552 486 512 480 C500 590 470 700 396 776 \
        C330 830 200 812 140 720 C86 636 82 470 130 350 \
        C176 232 258 130 350 130 Z
        """,
        discs: [Disc(cx: 300, cy: 340, r: 62)],
        fill: .solid(0xFFFFFF),
        evenOdd: true)

    // MARK: - AppKit rendering

    /// The full-colour badge, aspect-fitted and centred in `rect`.
    static func draw(in rect: NSRect) {
        render([badge] + features,
               source: NSRect(x: 0, y: 0, width: canvas, height: canvas),
               in: rect)
    }

    /// The white silhouette, aspect-fitted and centred in `rect`.
    static func drawMono(in rect: NSRect) {
        render([mono], source: bezier(for: mono).bounds, in: rect)
    }

    /// Full-colour mark as a square image (popover header, About, …).
    static func image(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(in: rect)
            return true
        }
    }

    /// White silhouette as a menu bar template image: macOS paints it white on
    /// the dark menu bar and inverts it automatically on a light one.
    static func menuBarImage(height: CGFloat = 18) -> NSImage {
        let bounds = bezier(for: mono).bounds
        let width = (height * bounds.width / bounds.height).rounded()
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            drawMono(in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "MitthuAI"
        return image
    }

    private static func render(_ elements: [Element], source: NSRect, in rect: NSRect) {
        guard source.width > 0, source.height > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        // Aspect-fit `source` into `rect`, then flip y so the shapes below can
        // be written in SVG coordinates.
        let scale = min(rect.width / source.width, rect.height / source.height)
        let originX = rect.minX + (rect.width - source.width * scale) / 2
        let originY = rect.minY + (rect.height - source.height * scale) / 2
        let transform = NSAffineTransform()
        transform.translateX(by: originX, yBy: originY + source.height * scale)
        transform.scale(by: scale)
        transform.scaleX(by: 1, yBy: -1)
        transform.translateX(by: -source.minX, yBy: -source.minY)
        transform.concat()

        for element in elements {
            let path = bezier(for: element)
            switch element.fill {
            case .solid(let hex):
                color(hex).setFill()
                path.fill()
            case .gradient(let top, let bottom):
                // 90° points along +y of the current (SVG) space, i.e. downward.
                NSGradient(starting: color(top), ending: color(bottom))?.draw(in: path, angle: 90)
            }
        }
    }

    private static func bezier(for element: Element) -> NSBezierPath {
        let path = element.d.isEmpty ? NSBezierPath() : bezier(element.d)
        for disc in element.discs {
            path.appendOval(in: NSRect(x: disc.cx - disc.r, y: disc.cy - disc.r,
                                       width: disc.r * 2, height: disc.r * 2))
        }
        path.windingRule = element.evenOdd ? .evenOdd : .nonZero
        return path
    }

    /// Minimal SVG path parser — absolute M/L/C/Z, which is all the artwork
    /// above uses.
    private static func bezier(_ d: String) -> NSBezierPath {
        let path = NSBezierPath()
        var command: Character = "M"
        var args: [CGFloat] = []
        var number = ""

        func takeNumber() {
            if let value = Double(number) { args.append(CGFloat(value)) }
            number = ""
        }
        func emit() {
            var i = 0
            switch command {
            case "M":
                while i + 1 < args.count {
                    let point = NSPoint(x: args[i], y: args[i + 1])
                    if i == 0 { path.move(to: point) } else { path.line(to: point) }
                    i += 2
                }
            case "L":
                while i + 1 < args.count {
                    path.line(to: NSPoint(x: args[i], y: args[i + 1]))
                    i += 2
                }
            case "C":
                while i + 5 < args.count {
                    path.curve(to: NSPoint(x: args[i + 4], y: args[i + 5]),
                               controlPoint1: NSPoint(x: args[i], y: args[i + 1]),
                               controlPoint2: NSPoint(x: args[i + 2], y: args[i + 3]))
                    i += 6
                }
            case "Z", "z":
                path.close()
            default:
                break
            }
            args.removeAll()
        }

        for ch in d {
            if ch.isLetter {
                if !number.isEmpty { takeNumber() }
                emit()
                command = ch
            } else if ch == "-" {
                if !number.isEmpty { takeNumber() }
                number = "-"
            } else if ch.isNumber || ch == "." {
                number.append(ch)
            } else {
                if !number.isEmpty { takeNumber() }
            }
        }
        if !number.isEmpty { takeNumber() }
        emit()
        return path
    }

    // MARK: - SVG rendering (dashboard)

    /// The full-colour mark as inline SVG, for the dashboard header. Self
    /// contained — no external file, so the page keeps working offline.
    static var svgMark: String {
        var body = ""
        for element in [badge] + features { body += svg(element) }
        return """
        <svg class="brand-mark" viewBox="0 0 1024 1024" role="img" aria-label="MitthuAI logo">\
        <defs><linearGradient id="mitthu-badge" x1="0" y1="0" x2="0" y2="1">\
        <stop offset="0" stop-color="\(hex(0xFF7A2B))"/><stop offset="1" stop-color="\(hex(0xE8431A))"/>\
        </linearGradient></defs>\(body)</svg>
        """
    }

    private static func hex(_ value: UInt32) -> String { String(format: "#%06X", value) }

    private static func svg(_ element: Element) -> String {
        let paint: String
        switch element.fill {
        case .solid(let value): paint = hex(value)
        case .gradient: paint = "url(#mitthu-badge)"
        }
        // A lone filled disc is simply a <circle>; anything else becomes a
        // <path>, with discs expressed as arc subpaths so holes survive.
        if element.d.isEmpty, element.discs.count == 1, !element.evenOdd {
            let disc = element.discs[0]
            return #"<circle cx="\#(num(disc.cx))" cy="\#(num(disc.cy))" r="\#(num(disc.r))" fill="\#(paint)"/>"#
        }
        var d = element.d
        for disc in element.discs {
            let top = num(disc.cy - disc.r), bottom = num(disc.cy + disc.r)
            let cx = num(disc.cx), r = num(disc.r)
            d += " M\(cx) \(top) A\(r) \(r) 0 1 1 \(cx) \(bottom) A\(r) \(r) 0 1 1 \(cx) \(top) Z"
        }
        let rule = element.evenOdd ? #" fill-rule="evenodd""# : ""
        return #"<path d="\#(d.replacingOccurrences(of: "\n", with: " "))" fill="\#(paint)"\#(rule)/>"#
    }

    private static func num(_ value: CGFloat) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%g", Double(value))
    }
}
