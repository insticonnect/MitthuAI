import Foundation
import ServiceManagement

/// "Open at Login" — lets macOS start MitthuAI automatically after every login
/// or reboot, so tracking is never silently off.
///
/// macOS 13+ uses the modern `SMAppService` registration (the app then shows up
/// in System Settings → General → Login Items). macOS 12 — and any machine where
/// that registration is refused — falls back to a plain LaunchAgent plist in
/// ~/Library/LaunchAgents, which launchd reads at login.
enum LoginItem {

    private static let agentLabel = "com.mitthuai.app.launchatlogin"

    private static var agentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    /// Only meaningful for a real .app bundle — a bare `swiftc` binary has
    /// nothing launchd could reopen.
    private static var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    /// True when macOS will reopen MitthuAI at the next login.
    static var isEnabled: Bool {
        guard isBundled else { return false }
        if #available(macOS 13.0, *) {
            if SMAppService.mainApp.status == .enabled { return true }
        }
        return FileManager.default.fileExists(atPath: agentPlistURL.path)
    }

    /// Turns the login item on or off. Returns the state we actually ended up
    /// in, which is what callers should store — registration can be refused.
    @discardableResult
    static func setEnabled(_ on: Bool) -> Bool {
        guard isBundled else { return false }

        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            if on && status == .requiresApproval {
                // The user switched us off in System Settings; only they can
                // switch it back on, and quietly writing a LaunchAgent would
                // just be sneaking around that.
                print("MitthuAI: login item needs approval in System Settings → General → Login Items.")
                return false
            }
            do {
                removeAgent()   // never leave a fallback agent double-launching us
                if on {
                    if status != .enabled { try SMAppService.mainApp.register() }
                } else {
                    if status == .enabled { try SMAppService.mainApp.unregister() }
                }
                return isEnabled
            } catch {
                print("MitthuAI: SMAppService \(on ? "register" : "unregister") failed (\(error)) — falling back to a LaunchAgent.")
            }
        }

        if on { writeAgent() } else { removeAgent() }
        return isEnabled
    }

    /// Called once at startup. A fresh install opts in — starting with the Mac
    /// is the point of a menu-bar tracker. After that macOS wins: both in-app
    /// toggles write through to it, so a mismatch means the user changed it in
    /// System Settings and we follow them instead of switching it back on.
    static func sync() {
        guard isBundled else { return }
        if !Config.shared.launchAtLoginStored {
            Config.shared.launchAtLogin = setEnabled(Config.shared.launchAtLogin)
            Config.shared.launchAtLoginStored = true
            Config.shared.save()
            return
        }
        let actual = isEnabled
        if actual != Config.shared.launchAtLogin {
            Config.shared.launchAtLogin = actual
            Config.shared.save()
        }
    }

    // MARK: - LaunchAgent fallback

    private static func writeAgent() {
        let plist: [String: Any] = [
            "Label": agentLabel,
            // `open -g` starts the bundle without stealing focus at login.
            "ProgramArguments": ["/usr/bin/open", "-g", Bundle.main.bundlePath],
            "RunAtLoad": true
        ]
        do {
            try FileManager.default.createDirectory(at: agentPlistURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: agentPlistURL, options: .atomic)
            launchctl(["bootstrap", "gui/\(getuid())", agentPlistURL.path])
        } catch {
            print("MitthuAI: could not write the login LaunchAgent: \(error)")
        }
    }

    private static func removeAgent() {
        guard FileManager.default.fileExists(atPath: agentPlistURL.path) else { return }
        launchctl(["bootout", "gui/\(getuid())/\(agentLabel)"])
        try? FileManager.default.removeItem(at: agentPlistURL)
    }

    /// Best effort: makes the change apply to this login session too. launchd
    /// picks the plist up at the next login either way, so failures are fine.
    private static func launchctl(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            // launchctl is unavailable — the plist alone still works at login.
        }
    }
}
