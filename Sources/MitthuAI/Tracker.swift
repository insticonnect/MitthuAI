import Cocoa
import Foundation
import Combine
import IOKit.pwr_mgt
import CoreAudio

/// The activity logger: samples the frontmost app/window every second,
/// writes timeline events on change, detects idle, and flags watched videos.
/// (Ported and extended from the field-tested mitthu tracker.)
final class Tracker: ObservableObject {
    @Published var currentAppName: String = "Starting…"
    @Published var currentWindowTitle: String = ""
    @Published var isIdle: Bool = false

    private let store: Store
    private var timer: Timer?
    private var lastEventStart = Date()
    private var lastAppName = ""
    private var lastWindowTitle = ""
    private var lastURL: String? = nil
    private var lastIsIdle = false
    /// Playback evidence collected during the current window session.
    private var sessionSignals = Extractors.PlayerSignals()
    /// Watch time per video, surviving tab-aways: flicking to WhatsApp
    /// mid-lecture doesn't reset the clock — the pieces add up. Keyed by URL
    /// when there is one (an SPA portal keeps one title for every lecture),
    /// else by title. `credited` is how much of `total` has already been
    /// written to the Brain entry, so repeated session closes with a growing
    /// total never double-count. `titleSecs` is how long each title held the
    /// screen for this video — see `dominantTitle`. An entry dies after 10
    /// minutes out of sight (the rules engine uses the same ±10 min).
    private var dwell: [String: (total: Double, signals: Extractors.PlayerSignals,
                                 firstTs: Double, lastSeen: Double, credited: Double,
                                 titleSecs: [String: Double])] = [:]

    private let idleThreshold: TimeInterval = 300

    var onWindowChange: (() -> Void)? = nil

    init(store: Store) {
        self.store = store
    }

    func start() {
        lastEventStart = Date()
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
        if Config.shared.paused {
            // Close out whatever was open and idle-park the tracker.
            if lastAppName != "Paused" {
                saveCurrentEvent()
                lastAppName = "Paused"; lastWindowTitle = ""; lastIsIdle = true
                lastEventStart = Date()
                currentAppName = "Paused"; currentWindowTitle = ""; isIdle = true
            }
            return
        }

        let anyInput = CGEventType(rawValue: ~0)!
        let idleSecs = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
        var nowIsIdle = idleSecs >= idleThreshold
        // Playing media holds display sleep off — both a reason not to call this
        // idle and evidence that the front window is playing something.
        let mediaAwake = isDisplaySleepPrevented()
        if nowIsIdle && mediaAwake {
            nowIsIdle = false // Watching a video counts as active.
        }
        if mediaAwake && !nowIsIdle { sessionSignals.mediaAssertion = true }
        // Sound actually coming out of the speakers — catches audio-only
        // lectures and video embeds alike (system-wide, so corroborating only).
        if !nowIsIdle && isAudioPlaying() { sessionSignals.audio = true }

        var activeApp = "Idle"
        var activeTitle = ""

        if !nowIsIdle, let details = AXReader.frontmostDetails() {
            let name = details.app.localizedName ?? "Unknown"
            if name == "loginwindow" {
                nowIsIdle = true
            } else {
                activeApp = name
                activeTitle = details.title
                // URL is carried on `lastURL`, refreshed by ContentCapture and
                // read directly in saveCurrentEvent().
            }
        }

        if activeApp != lastAppName || activeTitle != lastWindowTitle || nowIsIdle != lastIsIdle {
            saveCurrentEvent()
            sessionSignals = Extractors.PlayerSignals()  // evidence belonged to the session just closed
            lastAppName = activeApp
            lastWindowTitle = activeTitle
            lastIsIdle = nowIsIdle
            lastEventStart = Date()

            DispatchQueue.main.async {
                self.currentAppName = activeApp
                self.currentWindowTitle = activeTitle
                self.isIdle = nowIsIdle
            }
            onWindowChange?()
        }
    }

    /// Called from the capture queue with the freshest browser URL, so it hops
    /// to the main thread where session state lives. A changed URL under an
    /// unchanged title is an SPA moving to the next lecture: close the session
    /// (still carrying the OLD url) so watch time lands on the right video.
    /// Compared as full strings — fragment-routing SPAs ("/#/lesson/12") need
    /// the fragment.
    func noteURL(_ url: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let old = self.lastURL, let new = url, !old.isEmpty, !new.isEmpty,
               old != new, !self.lastIsIdle, !self.lastAppName.isEmpty, self.lastAppName != "Paused" {
                self.saveCurrentEvent()
                self.sessionSignals = Extractors.PlayerSignals()
                self.lastEventStart = Date()
            }
            self.lastURL = url
        }
    }

    /// Playback evidence from the latest content capture, accumulated for as
    /// long as this window stays in front. Called from the capture queue, so it
    /// hops to the main thread where the rest of `sessionSignals` is touched.
    func noteVideoSignals(_ signals: Extractors.PlayerSignals) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.sessionSignals = self.sessionSignals.merging(signals)
        }
    }

    private func saveCurrentEvent() {
        let now = Date()
        let duration = now.timeIntervalSince(lastEventStart)
        guard duration > 0.5, !lastAppName.isEmpty, lastAppName != "Paused" else { return }

        store.insertEvent(app: lastIsIdle ? "Idle" : lastAppName,
                          title: lastIsIdle ? "" : lastWindowTitle,
                          url: lastIsIdle ? nil : lastURL,
                          start: lastEventStart, end: now,
                          isIdle: lastIsIdle)

        // Accumulate watch time for this video. Detection judges the total —
        // not one continuous stretch — so tab-switching away and back keeps
        // counting; 60s is the floor detectWatched could possibly accept, and
        // its evidence-strength thresholds still apply to the total. Only the
        // uncredited slice is handed over, so the Brain entry's minutes grow
        // by exactly what was newly watched. A URL is enough to go on by
        // itself, so a stretch that arrives without a window title still counts
        // towards the video it belongs to.
        let canonical = Extractors.canonicalURL(lastURL) ?? ""
        if !lastIsIdle && (!lastWindowTitle.isEmpty || !canonical.isEmpty) {
            let nowTs = now.timeIntervalSince1970
            // One video, one key. The old key mixed in the window title, so
            // going fullscreen — or the player rewriting its own address — split
            // a single lecture into pieces that each restarted the watch clock
            // and never cleared the bar to be recorded at all.
            let key = canonical.isEmpty ? "t|" + lastAppName + "|" + lastWindowTitle
                                        : "u|" + lastAppName + "|" + canonical
            var d = dwell[key] ?? (0, Extractors.PlayerSignals(),
                                   lastEventStart.timeIntervalSince1970, nowTs, 0,
                                   [String: Double]())
            d.total += duration
            d.signals = d.signals.merging(sessionSignals)
            d.lastSeen = nowTs
            if !lastWindowTitle.isEmpty { d.titleSecs[lastWindowTitle, default: 0] += duration }
            if d.total >= 60 {
                let recorded = Extractors.detectWatched(app: lastAppName,
                                                        title: Tracker.dominantTitle(d.titleSecs),
                                                        url: lastURL, ts: d.firstTs,
                                                        duration: d.total, newSecs: d.total - d.credited,
                                                        signals: d.signals, store: store)
                if recorded { d.credited = d.total }
            }
            dwell[key] = d
            dwell = dwell.filter { nowTs - $0.value.lastSeen < 600 }
        }
    }

    /// What this video is called: the title that actually held the screen for
    /// it, by seconds.
    ///
    /// The window title and the browser URL are read by two different clocks —
    /// the title every second from the accessibility tree, the URL only when the
    /// ten-second content capture asks the browser for it. So for a moment after
    /// you move to the next lecture, the new title is already being seen while
    /// the address is still the old one, and that instant lands the wrong name
    /// on the wrong video. This used to keep whichever title was *longest*,
    /// which turned that instant into a permanent verdict: one lecture's name
    /// stuck to another's entry and no later, shorter, correct title could
    /// dislodge it. A few seconds of overlap can never outvote the minutes
    /// actually watched. Ties break on the title itself, so the answer is stable.
    private static func dominantTitle(_ titleSecs: [String: Double]) -> String {
        var best = "", bestSecs = -1.0
        for (title, secs) in titleSecs.sorted(by: { $0.key < $1.key }) where secs > bestSecs {
            best = title
            bestSecs = secs
        }
        return best
    }

    /// Whether the default output device is playing for anyone right now.
    /// Public CoreAudio, no permissions, a couple of mach calls per tick.
    private func isAudioPlaying() -> Bool {
        var deviceId = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &addr, 0, nil, &size, &deviceId) == noErr,
              deviceId != kAudioObjectUnknown else { return false }

        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        addr.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(deviceId, &addr, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    private func isDisplaySleepPrevented() -> Bool {
        var assertions: Unmanaged<CFDictionary>?
        let result = IOPMCopyAssertionsStatus(&assertions)
        if result == kIOReturnSuccess, let dict = assertions?.takeRetainedValue() as? [String: Any] {
            if let level = dict[kIOPMAssertionTypePreventUserIdleDisplaySleep] as? Int {
                return level > 0
            }
            if let level = dict["PreventUserIdleDisplaySleep"] as? Int {
                return level > 0
            }
        }
        return false
    }
}
