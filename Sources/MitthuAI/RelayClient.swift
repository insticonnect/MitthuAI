import Foundation

/// Outbound WebSocket tunnel to relay.mitthuai.com.
///
/// The relay lets Claude.ai on the web reach this Mac's local memory without
/// exposing any inbound port. Flow:
///   1. The app signs in with Google (SignIn.swift) → account token in Keychain.
///   2. This client opens an authenticated outbound WSS to the relay and
///      registers this device under the account.
///   3. When a paired Claude session issues an MCP call, the relay forwards the
///      raw JSON-RPC frame down this socket; we run it against the LOCAL
///      McpServer and send the response back up. Raw memory never leaves the
///      Mac — only the retrieved snippets travel.
///
/// Envelope on the wire (relay ⇄ app):
///   { "rid": "<opaque>", "mcp": { <json-rpc request> } }   relay → app
///   { "rid": "<opaque>", "mcp": { <json-rpc response> } }  app → relay
/// A frame with no "rid" and {"type":"ping"} is a keepalive.
final class RelayClient: NSObject, URLSessionWebSocketDelegate {
    private let store: Store
    private let mcp: McpServer
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var running = false
    private var reconnectDelay: TimeInterval = 2

    init(store: Store) {
        self.store = store
        self.mcp = McpServer(store: store)
        super.init()
        self.session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    /// Enabled only when the user has connected an account and a relay URL is set.
    static var isConfigured: Bool {
        return Config.shared.relayEnabled
            && !Config.shared.relayURL.isEmpty
            && (Keychain.get("account_token")?.isEmpty == false)
    }

    func start() {
        guard RelayClient.isConfigured else {
            print("MitthuAI Relay: not configured (sign in from the dashboard to enable Claude web access).")
            return
        }
        running = true
        connect()
    }

    func stop() {
        running = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func connect() {
        guard running,
              let token = Keychain.get("account_token"),
              var comps = URLComponents(string: Config.shared.relayURL) else { return }
        // e.g. wss://relay.mitthuai.com/agent
        if comps.path.isEmpty || comps.path == "/" { comps.path = "/agent" }
        guard let url = comps.url else { return }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(deviceId(), forHTTPHeaderField: "X-Device-Id")

        let t = session.webSocketTask(with: req)
        task = t
        t.resume()
        receive()
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure:
                self.scheduleReconnect()
            case .success(let message):
                switch message {
                case .string(let s): self.handleFrame(Data(s.utf8))
                case .data(let d):   self.handleFrame(d)
                @unknown default:    break
                }
                self.receive() // keep listening
            }
        }
    }

    private func handleFrame(_ data: Data) {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }

        if let type = obj["type"] as? String, type == "ping" {
            sendJSON(["type": "pong"])
            return
        }
        guard let rid = obj["rid"],
              let mcp = obj["mcp"],
              let mcpData = try? JSONSerialization.data(withJSONObject: mcp) else { return }

        // Run the MCP request against the LOCAL server.
        if let response = self.mcp.processRPC(mcpData),
           let responseObj = try? JSONSerialization.jsonObject(with: response) {
            sendJSON(["rid": rid, "mcp": responseObj])
        }
        // Notifications (nil response) get no reply, matching MCP semantics.
    }

    private func sendJSON(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let str = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(str)) { _ in }
    }

    private func scheduleReconnect() {
        guard running else { return }
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 60) // exponential backoff, capped
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect()
        }
    }

    /// Stable per-install device id (kept in Keychain).
    private func deviceId() -> String {
        if let id = Keychain.get("device_id") { return id }
        let id = UUID().uuidString
        Keychain.set("device_id", id)
        return id
    }

    // MARK: URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol proto: String?) {
        reconnectDelay = 2 // reset backoff on a good connection
        sendJSON(["type": "register", "device_id": deviceId(), "app": "mitthuai", "version": "1.0"])
        print("MitthuAI Relay: connected to \(Config.shared.relayURL)")
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        scheduleReconnect()
    }
}
