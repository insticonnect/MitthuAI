// Generates MitthuAI's app icon (a stylized parrot — "mitthu") as an .iconset
// of PNGs, which build.sh packs into AppIcon.icns with iconutil.
//
// Everything is drawn with AppKit vectors at each output size, so there is no
// binary art to keep in the repo and every size stays crisp.
//
//   swiftc -O Tools/MakeIcon.swift -o /tmp/makeicon && /tmp/makeicon <out.iconset>

import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0, alpha: 1)
}

/// One rotated teardrop of the head crest.
func feather(cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat, angle: CGFloat, fill: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform()
    t.translateX(by: cx, yBy: cy)
    t.rotate(byDegrees: angle)
    t.concat()
    fill.setFill()
    NSBezierPath(ovalIn: NSRect(x: -w / 2, y: -h / 2, width: w, height: h)).fill()
    NSGraphicsContext.restoreGraphicsState()
}

func drawIcon() {
    // Rounded-square plate, inset like a native macOS icon.
    let plate = NSBezierPath(roundedRect: NSRect(x: 96, y: 96, width: 832, height: 832),
                             xRadius: 186, yRadius: 186)
    NSGradient(starting: color(0x8B7BFF), ending: color(0x22C08A))?
        .draw(in: plate, angle: -90)

    // Crest, tucked behind the head.
    feather(cx: 410, cy: 690, w: 74, h: 180, angle: -20, fill: color(0xFFC15E))
    feather(cx: 470, cy: 712, w: 74, h: 190, angle: 0, fill: color(0xFFB454))
    feather(cx: 530, cy: 690, w: 74, h: 180, angle: 20, fill: color(0xFF9F45))

    // Head.
    color(0xFFFFFF).setFill()
    NSBezierPath(ovalIn: NSRect(x: 295, y: 345, width: 350, height: 350)).fill()

    // Hooked beak.
    let beak = NSBezierPath()
    beak.move(to: NSPoint(x: 600, y: 610))
    beak.curve(to: NSPoint(x: 800, y: 560),
               controlPoint1: NSPoint(x: 700, y: 640), controlPoint2: NSPoint(x: 772, y: 622))
    beak.curve(to: NSPoint(x: 718, y: 438),
               controlPoint1: NSPoint(x: 812, y: 500), controlPoint2: NSPoint(x: 772, y: 452))
    beak.curve(to: NSPoint(x: 600, y: 482),
               controlPoint1: NSPoint(x: 678, y: 428), controlPoint2: NSPoint(x: 628, y: 452))
    beak.close()
    color(0xFF7A59).setFill()
    beak.fill()

    // Eye + highlight.
    color(0x0E0F13).setFill()
    NSBezierPath(ovalIn: NSRect(x: 492, y: 548, width: 64, height: 64)).fill()
    color(0xFFFFFF).setFill()
    NSBezierPath(ovalIn: NSRect(x: 516, y: 578, width: 22, height: 22)).fill()
}

func render(px: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let t = NSAffineTransform()
    t.scale(by: CGFloat(px) / canvas)
    t.concat()
    drawIcon()
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// MARK: - main

let args = CommandLine.arguments
guard args.count > 1 else {
    FileHandle.standardError.write(Data("usage: makeicon <out.iconset>\n".utf8))
    exit(2)
}
let outDir = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// (file name, pixel size) pairs required by iconutil.
let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for (name, px) in sizes {
    guard let data = render(px: px) else {
        FileHandle.standardError.write(Data("failed rendering \(name)\n".utf8))
        exit(1)
    }
    try? data.write(to: outDir.appendingPathComponent(name))
}
