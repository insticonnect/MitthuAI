import Cocoa
import SwiftUI

/// Global handles shared across subsystems.
final class AppState {
    static let shared = AppState()
    var tracker: Tracker?
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    let popover = NSPopover()

    var store: Store!
    var tracker: Tracker!
    var capture: ContentCapture!
    var scheduler: ReminderScheduler!
    var httpServer: HttpServer!
    var relay: RelayClient!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ask for Accessibility permission (shows the System Settings prompt).
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if !trusted {
            print("MitthuAI: waiting for Accessibility permission — grant it in System Settings → Privacy & Security → Accessibility, then relaunch if capture stays empty.")
        }

        store = Store()
        Config.shared.load(from: store)

        // Start with macOS from now on (opt-in happens on the first launch;
        // afterwards this just mirrors whatever the user chose).
        LoginItem.sync()

        tracker = Tracker(store: store)
        AppState.shared.tracker = tracker

        capture = ContentCapture(store: store)
        tracker.onWindowChange = { [weak self] in
            self?.capture.windowChanged()
        }

        scheduler = ReminderScheduler(store: store)
        httpServer = HttpServer(store: store)
        relay = RelayClient(store: store)

        // Restart the relay tunnel whenever the account gets (re)paired.
        AccountPairing.shared.onPaired = { [weak self] in
            self?.relay.stop()
            self?.relay.start()
        }

        tracker.start()
        capture.start()
        scheduler.start()
        httpServer.start()
        relay.start()   // no-op unless an account is paired

        setupMenuBar()
        print("MitthuAI: running. Dashboard: \(httpServer.dashboardURL)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        tracker?.stop()
        capture?.stop()
        scheduler?.stop()
        httpServer?.stop()
        relay?.stop()
    }

    private func setupMenuBar() {
        let contentView = MenuBarView(tracker: tracker, store: store) { [weak self] in
            self?.openDashboard()
        }
        popover.contentSize = NSSize(width: 280, height: 340)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            // The mitthuai.com parrot, as a white template image: macOS paints
            // it white on the dark menu bar and inverts it on a light one. The
            // SF Symbol is a last resort so the item can never go invisible.
            button.image = BrandLogo.menuBarImage()
                ?? NSImage(systemSymbolName: "bird.fill", accessibilityDescription: "MitthuAI")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func openDashboard() {
        if let url = URL(string: httpServer.dashboardURL) {
            NSWorkspace.shared.open(url)
        }
        popover.performClose(nil)
    }
}
