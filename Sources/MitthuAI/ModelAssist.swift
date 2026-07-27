import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Optional last-resort date reading by Apple's on-device model.
///
/// Deliberately narrow. The deterministic parser in `DateParse` handles the
/// formats people actually write, runs in microseconds, and can't invent an
/// answer — so this is only asked about lines that mention a deadline and that
/// the parser could not resolve (or could only resolve ambiguously). That's a
/// handful of lines a day, not the 10-second capture firehose.
///
/// Three gates, any of which keeps it out of the way entirely:
///   • `#if canImport(FoundationModels)` — pre-macOS-26 SDKs compile this out
///   • `#available(macOS 26, *)` + the model's own availability check
///   • `Config.modelAssist`, off by default
///
/// Everything it returns is verified against the source text before use: a
/// model that invents a date is worse than no date at all.
enum ModelAssist {

    /// Human-readable state for the Settings panel — including the honest
    /// "this binary wasn't built with it" case.
    static var status: String {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return "ready"
            case .unavailable(let reason):
                return "unavailable (\(reason))"
            @unknown default:
                return "unavailable"
            }
        }
        return "needs macOS 26 with Apple Intelligence"
        #else
        return "not built into this app (needs the macOS 26 SDK)"
        #endif
    }

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Cheap guards so a bad day can't turn into a battery drain: one request
    /// at a time, a modest hourly budget, and no repeats of the same line.
    private static let lock = NSLock()
    private static var inFlight = false
    private static var seen = Set<String>()
    private static var hourStart = Date().timeIntervalSince1970
    private static var usedThisHour = 0
    private static let hourlyBudget = 40

    private static func claim(_ line: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let now = Date().timeIntervalSince1970
        if now - hourStart > 3600 { hourStart = now; usedThisHour = 0 }
        guard !inFlight, usedThisHour < hourlyBudget, !seen.contains(line) else { return false }
        inFlight = true
        usedThisHour += 1
        seen.insert(line)
        if seen.count > 400 { seen.removeAll() }
        return true
    }

    private static func release() {
        lock.lock(); inFlight = false; lock.unlock()
    }

    struct Verdict {
        let ts: Double
        let title: String
    }

    /// One line, one short question — which is exactly the shape this model is
    /// good at. It decides whether the line is a real thing to do and, if so,
    /// gives back the date and a title that reads like a task instead of the
    /// clipped screen fragment.
    private static let instructions = """
    You read one line of text from a user's screen and decide whether it is a \
    real deadline or event THEY must act on — an application closing, a bill, \
    a meeting or webinar they were invited to. Marketing urgency ("shop now", \
    "sale ends", "last chance to buy") is NOT a task: answer NONE for those. \
    Answer NONE if there is no clear date. Otherwise answer with exactly one \
    line: YYYY-MM-DD | a short title of at most 8 words. No other words.
    """

    /// Judge a line the deterministic parser could not resolve.
    static func judge(line: String, completion: @escaping (Verdict) -> Void) {
        ask(line: line) { verdict in completion(verdict) }
    }

    /// Tidy an item that was already created: better title, and a date the
    /// model has to agree with. Used right after extraction and behind the
    /// per-item ✨ button.
    static func refine(factId: Int64, line: String, store: Store) {
        ask(line: line) { verdict in
            store.setFactTitle(id: factId, title: verdict.title)
            store.setFactDue(id: factId, dueTs: verdict.ts)
        }
    }

    private static func ask(line: String, completion: @escaping (Verdict) -> Void) {
        guard Config.shared.modelAssist, isAvailable, claim(line) else { return }
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            Task.detached(priority: .utility) {
                defer { release() }
                let prompt = "Today is \(DateParse.isoDay(Date())).\nLine: \(line)"
                do {
                    let session = LanguageModelSession(instructions: instructions)
                    let reply = try await session.respond(to: prompt)
                    if let v = validate(reply.content, against: line) {
                        await MainActor.run { completion(v) }
                    }
                } catch {
                    print("MitthuAI: on-device model failed — \(error)")
                }
            }
            return
        }
        #endif
        release()
    }

    /// A model answer is only usable if the text actually supports it: strict
    /// "YYYY-MM-DD | title", the day must appear as a number in the line (unless
    /// the line said it in words — "tomorrow" has no digits to check), an
    /// explicit year in the line must match, and it must pass the same sanity
    /// window every other date does. Anything else is thrown away: an invented
    /// date is worse than no date.
    static func validate(_ reply: String, against line: String) -> Verdict? {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.uppercased().hasPrefix("NONE") else { return nil }
        let parts = trimmed.split(separator: "|", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let head = parts.first else { return nil }

        let ns = head as NSString
        guard let m = try? NSRegularExpression(pattern: #"^(\d{4})-(\d{2})-(\d{2})$"#)
                .firstMatch(in: head, options: [],
                            range: NSRange(location: 0, length: ns.length)),
              let year = Int(ns.substring(with: m.range(at: 1))),
              let month = Int(ns.substring(with: m.range(at: 2))),
              let day = Int(ns.substring(with: m.range(at: 3))) else { return nil }

        let numbers = tokens(in: line)
        if DateParse.hasRelativeWord(in: line) {
            // "Join us tomorrow" carries no digits to check against, so the
            // answer just has to be near today.
            var comps = DateComponents()
            comps.year = year; comps.month = month; comps.day = day
            guard let d = Calendar.current.date(from: comps),
                  abs(d.timeIntervalSinceNow) <= 14 * 86400 else { return nil }
        } else {
            guard numbers.contains(day) else { return nil }
            let years = numbers.filter { $0 > 1900 && $0 < 2200 }
            if !years.isEmpty && !years.contains(year) { return nil }
        }

        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day; comps.hour = 9
        guard let date = Calendar.current.date(from: comps) else { return nil }
        let ts = date.timeIntervalSince1970
        guard DateParse.plausible(ts) else { return nil }

        let cleaned = parts.count > 1 ? parts[1] : ""
        let title = cleaned.isEmpty ? String(line.prefix(120)) : String(cleaned.prefix(120))
        return Verdict(ts: ts, title: title)
    }

    private static func tokens(in line: String) -> Set<Int> {
        var out = Set<Int>()
        let ns = line as NSString
        let re = try! NSRegularExpression(pattern: #"\b\d{1,4}\b"#)
        for m in re.matches(in: line, options: [], range: NSRange(location: 0, length: ns.length)) {
            if let v = Int(ns.substring(with: m.range)) { out.insert(v) }
        }
        return out
    }
}
