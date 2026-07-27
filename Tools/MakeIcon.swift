// Generates MitthuAI's app icon as an .iconset of PNGs, which build.sh packs
// into AppIcon.icns with iconutil.
//
// The parrot itself lives in Sources/MitthuAI/BrandLogo.swift — the same
// artwork the menu bar, the popover and the dashboard use — so this file only
// has to place it on a rounded-square plate the way macOS expects.
//
//   swiftc -O Tools/MakeIcon.swift Sources/MitthuAI/BrandLogo.swift -o makeicon
//   makeicon <out.iconset>
//
// (swiftc requires the file with top-level code to be named main.swift when
// more than one file is compiled, so build.sh copies this one into place.)

import AppKit

let canvas: CGFloat = 1024

func drawIcon() {
    // Rounded-square plate in the brand's ink, inset like a native macOS icon.
    let plate = NSBezierPath(roundedRect: NSRect(x: 96, y: 96, width: 832, height: 832),
                             xRadius: 186, yRadius: 186)
    NSGradient(starting: BrandLogo.color(0x252833), ending: BrandLogo.color(0x0E0F13))?
        .draw(in: plate, angle: -90)

    // The badge, centred and sized so it breathes inside the plate.
    let mark: CGFloat = 620
    BrandLogo.draw(in: NSRect(x: (canvas - mark) / 2, y: (canvas - mark) / 2,
                              width: mark, height: mark))
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
