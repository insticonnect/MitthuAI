import Foundation
import NaturalLanguage

/// A pluggable text-embedding backend. Backends are interchangeable; each
/// tags its vectors with `modelId` so mixed-dimension vectors can coexist in
/// the store and be compared only against same-model queries.
protocol EmbeddingBackend {
    var modelId: String { get }
    func embed(_ text: String) -> [Float]?
}

/// On-device, private, free, English-only. Apple's NaturalLanguage sentence
/// embedding (512-dim). Default + offline fallback.
final class AppleEmbeddingBackend: EmbeddingBackend {
    let modelId = "apple-nl-en"
    private let model = NLEmbedding.sentenceEmbedding(for: .english)
    private let lock = NSLock()

    var available: Bool { model != nil }

    func embed(_ text: String) -> [Float]? {
        guard let m = model else { return nil }
        let t = String(text.prefix(1000)).replacingOccurrences(of: "\n", with: " ")
        guard !t.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        lock.lock(); defer { lock.unlock() }
        guard let v = m.vector(for: t) else { return nil }
        return v.map { Float($0) }
    }
}

/// Bring-your-own-key OpenAI backend ("Turbo accuracy"). Off by default; the
/// key is read from the Keychain. Sends text off-device, so it's strictly
/// opt-in. `text-embedding-3-small` → 1536-dim, multilingual.
final class OpenAIEmbeddingBackend: EmbeddingBackend {
    let modelId = "openai-3-small"
    private let apiKey: String

    init(apiKey: String) { self.apiKey = apiKey }

    func embed(_ text: String) -> [Float]? {
        let t = String(text.prefix(6000))
        guard !t.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let url = URL(string: "https://api.openai.com/v1/embeddings") else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = ["model": "text-embedding-3-small", "input": t]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        var vec: [Float]? = nil
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, _, _ in
            defer { sem.signal() }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = json["data"] as? [[String: Any]],
                  let first = arr.first,
                  let nums = first["embedding"] as? [Double] else { return }
            vec = nums.map { Float($0) }
        }.resume()
        _ = sem.wait(timeout: .now() + 16)
        return vec
    }
}

/// Facade that routes to the active backend based on Config, with the Apple
/// backend as fallback. Existing static vector helpers preserved.
final class Embeddings {
    static let shared = Embeddings()

    private let apple = AppleEmbeddingBackend()
    private var openai: OpenAIEmbeddingBackend?
    private var openaiKeyLoaded: String?

    private init() {}

    /// True when *some* embedding backend can produce vectors.
    var available: Bool { apple.available || activeIsOpenAI }

    private var activeIsOpenAI: Bool {
        Config.shared.turboEmbeddings && (Keychain.get("openai_api_key")?.isEmpty == false)
    }

    private func backend() -> EmbeddingBackend {
        if activeIsOpenAI, let key = Keychain.get("openai_api_key") {
            if openai == nil || openaiKeyLoaded != key {
                openai = OpenAIEmbeddingBackend(apiKey: key)
                openaiKeyLoaded = key
            }
            return openai!
        }
        return apple
    }

    /// Active model id (recorded alongside stored vectors).
    var modelId: String { backend().modelId }

    /// Human-readable description for the dashboard.
    var describe: String {
        if activeIsOpenAI { return "OpenAI text-embedding-3-small (Turbo, your key)" }
        return apple.available ? "Apple on-device (English)" : "unavailable (keyword-only)"
    }

    func embed(_ text: String) -> [Float]? {
        let b = backend()
        if let v = b.embed(text) { return v }
        // Fall back to Apple if the primary backend fails (e.g. network down).
        if b.modelId != apple.modelId { return apple.embed(text) }
        return nil
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<min(a.count, b.count) {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = (na.squareRoot() * nb.squareRoot())
        return denom > 0 ? dot / denom : 0
    }

    static func data(from vec: [Float]) -> Data {
        return vec.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func floats(from data: Data) -> [Float] {
        var arr = [Float](repeating: 0, count: data.count / MemoryLayout<Float>.size)
        _ = arr.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return arr
    }
}
