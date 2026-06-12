import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    let popover = NSPopover()
    var database = Database()
    var tracker: Tracker?
    var httpServer: HttpServer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request Accessibility permissions on launch
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        // Update Launch Agent path on startup if auto-start is enabled
        if HttpServer.isLaunchAtLoginEnabled() {
            HttpServer.setLaunchAtLogin(enabled: true)
        }
        
        // Initialize and start tracker
        tracker = Tracker(database: database)
        tracker?.start()
        
        // Start HTTP Server
        httpServer = HttpServer(database: database)
        httpServer?.start()
        
        // Setup Popover
        let contentView = DashboardView(database: database, tracker: tracker!)
        popover.contentSize = NSSize(width: 360, height: 480)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)
        
        // Setup Menu Bar Status Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            if #available(macOS 11.0, *) {
                button.image = NSImage(systemSymbolName: "bird", accessibilityDescription: "Mitthu")
            } else {
                button.image = NSImage(named: NSImage.networkName)
            }
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        print("Mitthu: Menu bar application started successfully.")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        tracker?.stop()
        httpServer?.stop()
        print("Mitthu: Terminating application.")
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = statusItem?.button {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }
}
