import Foundation
import Darwin

struct HttpRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data
}

/// Minimal localhost-only HTTP server. Serves the dashboard, the JSON API,
/// and the MCP endpoint. Binds 127.0.0.1 exclusively and requires the
/// bearer token for everything except the root landing check.
final class HttpServer {
    private let store: Store
    private let api: Api
    private let mcp: McpServer
    private var listenSocket: Int32 = -1
    private var running = false

    init(store: Store) {
        self.store = store
        self.api = Api(store: store)
        self.mcp = McpServer(store: store)
    }

    var port: UInt16 { Config.shared.port }
    var dashboardURL: String { "http://localhost:\(port)/?token=\(store.apiToken)" }
    var mcpURL: String { "http://localhost:\(port)/mcp" }

    func start() {
        listenSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard listenSocket >= 0 else {
            print("MitthuAI HTTP: socket() failed")
            return
        }
        var optVal: Int32 = 1
        setsockopt(listenSocket, SOL_SOCKET, SO_REUSEADDR, &optVal, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1") // localhost ONLY

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listenSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult >= 0 else {
            print("MitthuAI HTTP: bind failed on port \(port) — is another instance running?")
            return
        }
        guard listen(listenSocket, 16) >= 0 else {
            print("MitthuAI HTTP: listen failed")
            return
        }
        running = true
        print("MitthuAI HTTP: dashboard at \(dashboardURL)")

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        running = false
        if listenSocket >= 0 {
            close(listenSocket)
            listenSocket = -1
        }
    }

    private func acceptLoop() {
        while running {
            var clientAddr = sockaddr()
            var len = socklen_t(MemoryLayout<sockaddr>.size)
            let client = accept(listenSocket, &clientAddr, &len)
            if client < 0 { continue }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handle(client)
            }
        }
    }

    // MARK: - Request handling

    private func handle(_ client: Int32) {
        defer { close(client) }
        guard let request = readRequest(client) else { return }

        let authed = isAuthorized(request)
        let (status, contentType, body, extraHeaders) = route(request, authed: authed)

        var header = "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n"
        header += "Cache-Control: no-store\r\n"
        for (k, v) in extraHeaders { header += "\(k): \(v)\r\n" }
        header += "\r\n"

        var out = Data(header.utf8)
        out.append(body)
        out.withUnsafeBytes { raw in
            var sent = 0
            while sent < out.count {
                let n = send(client, raw.baseAddress!.advanced(by: sent), out.count - sent, 0)
                if n <= 0 { break }
                sent += n
            }
        }
    }

    private func readRequest(_ client: Int32) -> HttpRequest? {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 16384)
        var headerEnd: Range<Data.Index>? = nil

        // Read until end of headers.
        while headerEnd == nil {
            let n = recv(client, &chunk, chunk.count, 0)
            if n <= 0 { return nil }
            buffer.append(contentsOf: chunk[0..<n])
            headerEnd = buffer.range(of: Data("\r\n\r\n".utf8))
            if buffer.count > 1_048_576 { return nil }
        }

        guard let he = headerEnd else { return nil }
        let headerData = buffer.subdata(in: buffer.startIndex..<he.lowerBound)
        guard let headerStr = String(data: headerData, encoding: .utf8) else { return nil }
        var lines = headerStr.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }

        let requestLine = lines.removeFirst().components(separatedBy: " ")
        guard requestLine.count >= 2 else { return nil }
        let method = requestLine[0]
        let fullPath = requestLine[1]

        var headers: [String: String] = [:]
        for line in lines {
            if let idx = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<idx]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        // Read remaining body per Content-Length.
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        var body = buffer.subdata(in: he.upperBound..<buffer.endIndex)
        while body.count < contentLength {
            let n = recv(client, &chunk, chunk.count, 0)
            if n <= 0 { break }
            body.append(contentsOf: chunk[0..<n])
            if body.count > 8_388_608 { return nil }
        }

        // Split path / query string.
        var path = fullPath
        var query: [String: String] = [:]
        if let qIdx = fullPath.firstIndex(of: "?") {
            path = String(fullPath[fullPath.startIndex..<qIdx])
            let qs = String(fullPath[fullPath.index(after: qIdx)...])
            for pair in qs.components(separatedBy: "&") {
                let kv = pair.components(separatedBy: "=")
                if kv.count == 2 {
                    query[kv[0]] = kv[1].removingPercentEncoding?.replacingOccurrences(of: "+", with: " ") ?? kv[1]
                }
            }
        }

        return HttpRequest(method: method, path: path, query: query, headers: headers, body: body)
    }

    private func isAuthorized(_ req: HttpRequest) -> Bool {
        let token = store.apiToken
        if req.query["token"] == token { return true }
        if let auth = req.headers["authorization"], auth == "Bearer \(token)" { return true }
        return false
    }

    // MARK: - Routing

    private func route(_ req: HttpRequest, authed: Bool) -> (String, String, Data, [String: String]) {
        // Dashboard page — needs token in URL (it then keeps it in localStorage).
        if req.method == "GET" && req.path == "/" {
            if authed {
                return ("200 OK", "text/html; charset=utf-8", Data(DashboardHTML.page.utf8), [:])
            }
            let msg = "<html><body style='font-family:sans-serif;background:#111;color:#eee;padding:3em'>" +
                      "<h2>MitthuAI</h2><p>Missing or invalid token. Open the dashboard from the " +
                      "MitthuAI menu bar icon — it includes your access token.</p></body></html>"
            return ("403 Forbidden", "text/html; charset=utf-8", Data(msg.utf8), [:])
        }

        if req.path == "/mcp" {
            guard authed else {
                return ("401 Unauthorized", "application/json",
                        Data(#"{"error":"unauthorized"}"#.utf8), [:])
            }
            return mcp.handle(req)
        }

        if req.path.hasPrefix("/api/") {
            guard authed else {
                return ("401 Unauthorized", "application/json",
                        Data(#"{"error":"unauthorized"}"#.utf8), [:])
            }
            return api.handle(req)
        }

        return ("404 Not Found", "text/plain", Data("not found".utf8), [:])
    }
}
