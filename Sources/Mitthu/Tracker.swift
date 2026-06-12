import Cocoa
import Foundation
import Combine
import IOKit.pwr_mgt

class Tracker: ObservableObject {
    @Published var currentAppName: String = "Initializing..."
    @Published var currentWindowTitle: String = ""
    @Published var isIdle: Bool = false
    @Published var sessionDuration: TimeInterval = 0.0
    
    private var db: Database
    private var timer: Timer?
    private var lastEventStart: Date = Date()
    private var lastAppName: String = ""
    private var lastWindowTitle: String = ""
    private var lastIsIdle: Bool = false
    
    // 5 minutes (300 seconds) threshold for idle
    private let idleThreshold: TimeInterval = 300.0
    
    init(database: Database) {
        self.db = database
    }
    
    func start() {
        lastEventStart = Date()
        
        if let current = getActiveWindowDetails() {
            lastAppName = current.appName
            lastWindowTitle = current.windowTitle
            currentAppName = current.appName
            currentWindowTitle = current.windowTitle
        } else {
            lastAppName = "Idle"
            lastWindowTitle = ""
            currentAppName = "Idle"
            currentWindowTitle = ""
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
        saveCurrentEvent()
    }
    
    private func tick() {
        let anyInputEventType = CGEventType(rawValue: ~0)!
        let idleSecs = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInputEventType)
        var nowIsIdle = idleSecs >= idleThreshold
        
        if nowIsIdle && isDisplaySleepPrevented() {
            nowIsIdle = false
        }
        
        var activeApp = "Idle"
        var activeTitle = ""
        
        if !nowIsIdle {
            if let current = getActiveWindowDetails() {
                if current.appName == "loginwindow" {
                    nowIsIdle = true
                    activeApp = "Idle"
                    activeTitle = ""
                } else {
                    activeApp = current.appName
                    activeTitle = current.windowTitle
                }
            }
        }
        
        let now = Date()
        let elapsed = now.timeIntervalSince(lastEventStart)
        
        DispatchQueue.main.async {
            self.sessionDuration = elapsed
        }
        
        if activeApp != lastAppName || activeTitle != lastWindowTitle || nowIsIdle != lastIsIdle {
            saveCurrentEvent()
            
            lastAppName = activeApp
            lastWindowTitle = activeTitle
            lastIsIdle = nowIsIdle
            lastEventStart = now
            
            DispatchQueue.main.async {
                self.currentAppName = activeApp
                self.currentWindowTitle = activeTitle
                self.isIdle = nowIsIdle
                self.sessionDuration = 0.0
            }
        }
    }
    
    private func saveCurrentEvent() {
        let now = Date()
        let duration = now.timeIntervalSince(lastEventStart)
        if duration > 0.5 {
            db.insertEvent(
                appName: lastAppName,
                windowTitle: lastWindowTitle,
                startTime: lastEventStart,
                endTime: now,
                duration: duration,
                isIdle: lastIsIdle
            )
        }
    }
    
    private func getActiveWindowDetails() -> (appName: String, windowTitle: String)? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let appName = frontmostApp.localizedName ?? "Unknown"
        
        let pid = frontmostApp.processIdentifier
        let appRef = AXUIElementCreateApplication(pid)
        var windowRef: AnyObject?
        var result = AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)
        if result != .success {
            result = AXUIElementCopyAttributeValue(appRef, kAXMainWindowAttribute as CFString, &windowRef)
        }
        
        var windowTitle = ""
        if result == .success, let windowElement = windowRef as! AXUIElement? {
            var titleRef: AnyObject?
            let titleResult = AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &titleRef)
            if titleResult == .success, let title = titleRef as? String {
                windowTitle = title
            }
        } else {
            print("Mitthu AXError: Failed to copy window attribute for \(appName), error code: \(result.rawValue)")
        }
        
        return (appName, windowTitle)
    }
    
    private func isDisplaySleepPrevented() -> Bool {
        var assertionsStatus: Unmanaged<CFDictionary>?
        let result = IOPMCopyAssertionsStatus(&assertionsStatus)
        if result == kIOReturnSuccess, let statusDict = assertionsStatus?.takeRetainedValue() as? [String: Any] {
            if let level = statusDict[kIOPMAssertionTypePreventUserIdleDisplaySleep] as? Int {
                return level > 0
            }
            if let level = statusDict["PreventUserIdleDisplaySleep"] as? Int {
                return level > 0
            }
        }
        return false
    }
}
