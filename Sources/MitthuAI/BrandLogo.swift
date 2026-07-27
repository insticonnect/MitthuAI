import AppKit

/// MitthuAI's brand assets — the mitthuai.com logo, shipped as files under
/// `Resources/Brand` and copied into the app bundle by build.sh:
///
///   * `mitthuai-logo.png`     the logo itself, for the popover and dashboard
///   * `mitthuai-menubar.png`  the same artwork reduced to a white silhouette
///                             (its own beak and eye knocked out) for the menu
///                             bar, where 18pt is too small for full colour
///   * `icon.icon/`            the Icon Composer source the two come from;
///                             `Resources/AppIcon.icns` is built from it
///
/// Nothing here draws the parrot — swap the PNGs and every surface follows.
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

    // MARK: - Artwork

    private static func assetURL(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Brand")
    }

    /// Loaded PNGs, kept around because the popover re-renders every few
    /// seconds while it is open. Main thread only, like everything that asks.
    private static var loaded: [String: NSImage] = [:]

    private static func scaled(_ name: String, toHeight height: CGFloat) -> NSImage? {
        let base: NSImage
        if let cached = loaded[name] {
            base = cached
        } else {
            guard let url = assetURL(name), let image = NSImage(contentsOf: url),
                  image.size.height > 0 else { return nil }
            loaded[name] = image
            base = image
        }
        // Copy before resizing: the cached original keeps its own dimensions.
        guard let sized = base.copy() as? NSImage else { return nil }
        sized.size = NSSize(width: (height * base.size.width / base.size.height).rounded(),
                            height: height)
        return sized
    }

    /// The full-colour logo, sized to fit a `size`×`size` box.
    static func image(size: CGFloat) -> NSImage? {
        let image = scaled("mitthuai-logo", toHeight: size)
        image?.accessibilityDescription = "MitthuAI logo"
        return image
    }

    /// White silhouette as a menu bar template image: macOS paints it white on
    /// the dark menu bar and inverts it automatically on a light one.
    static func menuBarImage(height: CGFloat = 18) -> NSImage? {
        guard let image = scaled("mitthuai-menubar", toHeight: height) else { return nil }
        image.isTemplate = true
        image.accessibilityDescription = "MitthuAI"
        return image
    }

    /// The logo as a `data:` URI, so the dashboard carries it inline and keeps
    /// working with no network.
    static var logoDataURI: String {
        guard let url = assetURL("mitthuai-logo"), let data = try? Data(contentsOf: url) else {
            return ""
        }
        return "data:image/png;base64," + data.base64EncodedString()
    }
}
