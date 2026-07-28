import Cocoa
import ApplicationServices

struct AXSnapshot {
    let appName: String
    let bundleId: String
    let windowTitle: String
    let text: String
    /// Labels of interactive chrome (buttons, sliders) — kept out of `text` so
    /// the search corpus stays clean. This is where a web video player shows
    /// itself: its Play/Mute/Full-screen buttons and its seek slider
    /// ("0:14 of 12:45") are AX elements even while visually hidden.
    let controlsText: String
    let url: String?
}

/// Reads the frontmost window through the macOS Accessibility API — the same
/// tree VoiceOver walks — so we get real text without screenshots.
enum AXReader {

    static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var ref: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(el, name as CFString, &ref)
        return result == .success ? ref : nil
    }

    static func string(_ el: AXUIElement, _ name: String) -> String? {
        return attr(el, name) as? String
    }

    static func focusedWindow(pid: pid_t) -> AXUIElement? {
        let appRef = AXUIElementCreateApplication(pid)
        if let w = attr(appRef, kAXFocusedWindowAttribute as String) {
            return (w as! AXUIElement)
        }
        if let w = attr(appRef, kAXMainWindowAttribute as String) {
            return (w as! AXUIElement)
        }
        return nil
    }

    static func frontmostDetails() -> (app: NSRunningApplication, window: AXUIElement?, title: String)? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let window = focusedWindow(pid: front.processIdentifier)
        var title = ""
        if let w = window, let t = string(w, kAXTitleAttribute as String) {
            title = t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // A video playing fullscreen sits in a window that carries no title of
        // its own — and a blank title costs that stretch its category and the
        // video its watch time. Before settling for nothing, ask the app what
        // it has open: the document, then any window still holding a name
        // behind the fullscreen one.
        if title.isEmpty, let w = window, let doc = string(w, kAXDocumentAttribute as String), !doc.isEmpty {
            title = URL(string: doc)?.lastPathComponent ?? doc
        }
        if title.isEmpty {
            title = firstTitledWindow(pid: front.processIdentifier)
        }
        return (front, window, title)
    }

    /// The first window of this app that still has a name — what the browser
    /// goes on calling the page whose video went fullscreen.
    private static func firstTitledWindow(pid: pid_t) -> String {
        let appRef = AXUIElementCreateApplication(pid)
        guard let windows = attr(appRef, kAXWindowsAttribute as String) as? [AXUIElement] else { return "" }
        for w in windows.prefix(8) {
            guard let t = string(w, kAXTitleAttribute as String) else { continue }
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    /// Walk the AX tree of a window collecting user-visible text, plus — in the
    /// same pass — the labels of buttons and sliders. The latter come back
    /// separately: they're what identifies an embedded video player (Play,
    /// Mute, a seek slider reading "0:14 of 12:45"), but they'd be noise in
    /// the searchable text. Depth/node/char limited so a huge web page can't
    /// stall the app.
    static func extractText(from window: AXUIElement, maxChars: Int = 24000) -> (text: String, controls: String) {
        var pieces: [String] = []
        var controlPieces: [String] = []
        var totalChars = 0
        var controlChars = 0
        var visited = 0
        let maxControlChars = 2000

        let textRoles: Set<String> = [
            "AXStaticText", "AXTextField", "AXTextArea", "AXHeading",
            "AXLink", "AXCell", "AXComboBox", "AXPopUpButton"
        ]
        let controlRoles: Set<String> = ["AXButton", "AXSlider", "AXMenuButton"]

        func walk(_ el: AXUIElement, depth: Int) {
            if depth > 30 || visited > 3000 || totalChars >= maxChars { return }
            visited += 1

            let role = string(el, kAXRoleAttribute as String) ?? ""

            // Never read secure fields (passwords etc.)
            if let subrole = string(el, kAXSubroleAttribute as String), subrole == "AXSecureTextField" {
                return
            }

            if textRoles.contains(role) {
                var value = ""
                if let v = attr(el, kAXValueAttribute as String) as? String {
                    value = v
                } else if let t = string(el, kAXTitleAttribute as String) {
                    value = t
                }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count > 1 {
                    let clipped = String(trimmed.prefix(maxChars - totalChars))
                    pieces.append(clipped)
                    totalChars += clipped.count + 1
                }
            } else if controlRoles.contains(role) && controlChars < maxControlChars {
                // Web buttons usually label themselves via AXDescription; a
                // slider's value ("0:14 of 12:45" on a seek bar) is the payload.
                var parts: [String] = []
                for name in [kAXTitleAttribute as String, kAXDescriptionAttribute as String,
                             kAXValueDescriptionAttribute as String] {
                    if let s = string(el, name), !s.isEmpty { parts.append(s) }
                }
                if let v = attr(el, kAXValueAttribute as String) as? String, !v.isEmpty {
                    parts.append(v)
                }
                let joined = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                if joined.count > 1 {
                    let clipped = String(joined.prefix(maxControlChars - controlChars))
                    controlPieces.append(clipped)
                    controlChars += clipped.count + 1
                }
            }

            if totalChars >= maxChars { return }
            if let children = attr(el, kAXChildrenAttribute as String) as? [AXUIElement] {
                for child in children.prefix(120) {
                    walk(child, depth: depth + 1)
                    if totalChars >= maxChars || visited > 3000 { break }
                }
            }
        }

        walk(window, depth: 0)
        return (pieces.joined(separator: "\n"), controlPieces.joined(separator: "\n"))
    }

    /// Current URL of the frontmost browser tab, via Apple Events.
    /// Requires the Automation permission (prompted on first use).
    static func browserURL(bundleId: String) -> String? {
        let source: String
        switch bundleId {
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
            source = "tell application id \"\(bundleId)\" to return URL of front document"
        case "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac",
             "com.vivaldi.Vivaldi", "company.thebrowser.Browser":
            source = "tell application id \"\(bundleId)\" to return URL of active tab of front window"
        default:
            return nil
        }

        var url: String? = nil
        let work = {
            guard let script = NSAppleScript(source: source) else { return }
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            if error == nil {
                url = result.stringValue
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
        return url
    }

    static func isPrivateWindow(title: String) -> Bool {
        let t = title.lowercased()
        return t.contains("private browsing") || t.contains("incognito") || t.contains("(private)")
    }

    /// One full snapshot of the frontmost window: app, title, text, url.
    static func snapshot(captureText: Bool, captureURL: Bool) -> AXSnapshot? {
        guard let (app, window, title) = frontmostDetails() else { return nil }
        let appName = app.localizedName ?? "Unknown"
        let bundleId = app.bundleIdentifier ?? ""

        if Config.shared.isExcluded(app: appName) {
            return AXSnapshot(appName: appName, bundleId: bundleId, windowTitle: title, text: "", controlsText: "", url: nil)
        }
        if isPrivateWindow(title: title) {
            return AXSnapshot(appName: appName, bundleId: bundleId, windowTitle: title, text: "", controlsText: "", url: nil)
        }

        var text = ""
        var controlsText = ""
        if captureText, let w = window {
            (text, controlsText) = extractText(from: w)
        }
        var url: String? = nil
        if captureURL {
            url = browserURL(bundleId: bundleId)
        }
        return AXSnapshot(appName: appName, bundleId: bundleId, windowTitle: title, text: text, controlsText: controlsText, url: url)
    }
}
