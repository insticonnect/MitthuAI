import Foundation
import CryptoKit

/// Periodically snapshots the focused window's visible text, chunks it,
/// dedupes it, embeds it, and runs the fact extractors over it.
final class ContentCapture {
    private let store: Store
    private let queue = DispatchQueue(label: "com.mitthuai.capture", qos: .utility)
    private var timer: Timer?
    private var lastHash = ""

    // Recent embeddings (per app) for near-duplicate suppression. All capture
    // runs serialized on `queue`, so no extra locking is needed.
    private var recentVecs: [(app: String, vec: [Float])] = []
    private let nearDupThreshold: Float = 0.95

    init(store: Store) {
        self.store = store
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.captureAsync()
        }
        // First capture shortly after launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.captureAsync()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Called by the tracker when the focused window changes (debounced).
    func windowChanged() {
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.capture()
        }
    }

    func captureAsync() {
        queue.async { [weak self] in
            self?.capture()
        }
    }

    private func capture() {
        guard !Config.shared.paused else { return }
        guard let snap = AXReader.snapshot(captureText: Config.shared.captureText,
                                           captureURL: Config.shared.captureURLs) else { return }

        // Let the tracker record the URL on its timeline events too, along with
        // any sign that this window is playing a video. Control labels join the
        // scan here only — they stay out of the stored/embedded text.
        AppState.shared.tracker?.noteURL(snap.url)
        AppState.shared.tracker?.noteVideoSignals(
            Extractors.playerSignals(in: snap.text + "\n" + snap.controlsText))

        let text = snap.text
        guard text.count > 40 else { return }

        // Whole-screen dedupe: identical screen since last capture → skip early.
        let screenKey = hash(of: snap.appName + "|" + snap.windowTitle + "|" + text)
        if screenKey == lastHash { return }
        lastHash = screenKey

        let ts = Date().timeIntervalSince1970
        let day = Self.dayString(ts)

        // Context header makes each embedded vector self-describing.
        var header = snap.appName
        if !snap.windowTitle.isEmpty { header += " · " + snap.windowTitle }
        if let u = snap.url, !u.isEmpty { header += " · " + u }

        for chunkText in chunk(text) {
            // Per-day exact-content dedupe: same text seen again today is skipped.
            let h = hash(of: day + "|" + snap.appName + "|" + chunkText)

            // Embed with the context header prepended.
            let vec = Embeddings.shared.embed(header + "\n" + chunkText)

            // Near-duplicate suppression: near-identical screens (cosine > 0.95)
            // to something we captured recently in the same app are not stored.
            if let v = vec, isNearDuplicate(v, app: snap.appName) { continue }

            guard let chunkId = store.insertChunk(ts: ts, app: snap.appName,
                                                  title: snap.windowTitle,
                                                  url: snap.url, text: chunkText,
                                                  hash: h) else { continue }
            if let v = vec {
                store.insertEmbedding(chunkId: chunkId, vec: v, model: Embeddings.shared.modelId)
                rememberVec(v, app: snap.appName)
            }
        }

        // Facts are read from the whole screen, not per chunk: chunking exists
        // for embeddings, and a deadline in one chunk needs the sender that may
        // sit in another.
        Extractors.extractFacts(from: text,
                                source: "\(snap.appName): \(snap.windowTitle)",
                                store: store,
                                windowTitle: snap.windowTitle)
    }

    private func isNearDuplicate(_ vec: [Float], app: String) -> Bool {
        for entry in recentVecs where entry.app == app && entry.vec.count == vec.count {
            if Embeddings.cosine(entry.vec, vec) > nearDupThreshold { return true }
        }
        return false
    }

    private func rememberVec(_ vec: [Float], app: String) {
        recentVecs.append((app, vec))
        if recentVecs.count > 60 { recentVecs.removeFirst(recentVecs.count - 60) }
    }

    /// Split captured text into ~800-char chunks on sentence/line boundaries,
    /// carrying a small overlap so context isn't cut mid-thought.
    private func chunk(_ text: String, target: Int = 800, overlap: Int = 120, maxChunks: Int = 16) -> [String] {
        // Prefer sentence units; fall back to lines.
        var units: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let l = line.trimmingCharacters(in: .whitespaces)
            guard !l.isEmpty else { continue }
            if l.count > target {
                for s in l.split(whereSeparator: { $0 == "." || $0 == "!" || $0 == "?" }) {
                    let t = s.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { units.append(t) }
                }
            } else {
                units.append(l)
            }
        }

        var chunks: [String] = []
        var current = ""
        for u in units {
            if current.count + u.count + 1 > target && !current.isEmpty {
                chunks.append(current)
                if chunks.count >= maxChunks { return chunks }
                current = String(current.suffix(overlap)) // carry overlap
            }
            current += (current.isEmpty ? "" : "\n") + u
        }
        if !current.isEmpty && chunks.count < maxChunks { chunks.append(current) }
        return chunks
    }

    private func hash(of s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func dayString(_ ts: Double) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone.current
        return fmt.string(from: Date(timeIntervalSince1970: ts))
    }
}
