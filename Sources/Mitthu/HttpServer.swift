import Foundation
#if canImport(Darwin)
import Darwin
#endif

class HttpServer {
    private var listenSocket: Int32 = -1
    private var isRunning = false
    private let port: UInt16 = 5680
    private var db: Database
    
    init(database: Database) {
        self.db = database
    }
    
    func start() {
        guard !isRunning else { return }
        
        listenSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard listenSocket >= 0 else {
            print("Mitthu HTTP Server: Socket creation failed.")
            return
        }
        
        var optVal: Int32 = 1
        setsockopt(listenSocket, SOL_SOCKET, SO_REUSEADDR, &optVal, socklen_t(MemoryLayout<Int32>.size))
        
        var serverAddr = sockaddr_in()
        serverAddr.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
        serverAddr.sin_family = sa_family_t(AF_INET)
        serverAddr.sin_port = port.bigEndian
        serverAddr.sin_addr.s_addr = in_addr_t(0) // Bind to localhost/all
        
        let bindResult = withUnsafePointer(to: &serverAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        guard bindResult >= 0 else {
            print("Mitthu HTTP Server: Bind failed on port \(port).")
            return
        }
        
        guard listen(listenSocket, 15) >= 0 else {
            print("Mitthu HTTP Server: Listen failed.")
            return
        }
        
        isRunning = true
        print("Mitthu HTTP Server: Running at http://localhost:\(port)/")
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.acceptConnections()
        }
    }
    
    func stop() {
        isRunning = false
        if listenSocket >= 0 {
            close(listenSocket)
            listenSocket = -1
        }
    }
    
    private func acceptConnections() {
        while isRunning {
            var clientAddr = sockaddr()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr>.size)
            let clientSocket = accept(listenSocket, &clientAddr, &clientAddrLen)
            
            guard clientSocket >= 0 else { continue }
            
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.handleClient(clientSocket)
            }
        }
    }
    
    private func handleClient(_ clientSocket: Int32) {
        defer {
            shutdown(clientSocket, SHUT_WR)
            usleep(20000) // Sleep for 20ms to allow TCP flush
            close(clientSocket)
        }
        
        var requestData = Data()
        let tempBufferSize = 4096
        var tempBuffer = [UInt8](repeating: 0, count: tempBufferSize)
        
        var requestStr = ""
        var contentLength = 0
        var readCompleted = false
        var headersCompleted = false
        
        while !readCompleted {
            let bytesRead = read(clientSocket, &tempBuffer, tempBufferSize)
            if bytesRead <= 0 {
                break
            }
            requestData.append(contentsOf: tempBuffer[0..<bytesRead])
            
            if let currentStr = String(data: requestData, encoding: .utf8) {
                requestStr = currentStr
                if let range = requestStr.range(of: "\r\n\r\n") {
                    let headerPart = requestStr[..<range.lowerBound]
                    let bodyPart = requestStr[range.upperBound...]
                    
                    if !headersCompleted {
                        headersCompleted = true
                        let lines = headerPart.components(separatedBy: "\r\n")
                        for line in lines {
                            let parts = line.components(separatedBy: ":")
                            if parts.count >= 2 {
                                let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                                let val = parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
                                if key == "content-length", let len = Int(val) {
                                    contentLength = len
                                    break
                                }
                            }
                        }
                    }
                    
                    if bodyPart.utf8.count >= contentLength {
                        readCompleted = true
                    }
                }
            } else {
                break
            }
        }
        
        guard !requestStr.isEmpty else { return }
        
        let lines = requestStr.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return }
        
        let method = parts[0]
        let fullPath = parts[1]
        
        let urlComponents = URLComponents(string: fullPath)
        let path = urlComponents?.path ?? "/"
        
        if method == "GET" && path == "/" {
            serveDashboard(clientSocket)
        } else if method == "GET" && path == "/api/stats" {
            let dateStr = urlComponents?.queryItems?.first(where: { $0.name == "date" })?.value ?? ""
            let deviceStr = urlComponents?.queryItems?.first(where: { $0.name == "device" })?.value ?? "Mac"
            serveApiStats(clientSocket, dateStr: dateStr, deviceStr: deviceStr)
        } else if method == "GET" && path == "/api/weekly-stats" {
            let dateStr = urlComponents?.queryItems?.first(where: { $0.name == "date" })?.value ?? ""
            let deviceStr = urlComponents?.queryItems?.first(where: { $0.name == "device" })?.value ?? "Mac"
            serveApiWeeklyStats(clientSocket, dateStr: dateStr, deviceStr: deviceStr)
        } else if method == "GET" && path == "/api/rules" {
            serveApiRules(clientSocket)
        } else if method == "GET" && path == "/api/export" {
            let dateStr = urlComponents?.queryItems?.first(where: { $0.name == "date" })?.value ?? ""
            let deviceStr = urlComponents?.queryItems?.first(where: { $0.name == "device" })?.value ?? "Mac"
            serveApiExport(clientSocket, dateStr: dateStr, deviceStr: deviceStr)
        } else if method == "GET" && path == "/api/autostart" {
            serveApiAutoStart(clientSocket)
        } else if method == "POST" && path == "/api/autostart" {
            if let bodyRange = requestStr.range(of: "\r\n\r\n") {
                let body = String(requestStr[bodyRange.upperBound...])
                handlePostAutoStart(clientSocket, body: body)
            } else {
                sendJson(clientSocket, json: "{\"success\": false, \"error\": \"No body\"}", status: 400)
            }
        } else if method == "POST" && path == "/api/rules/delete" {
            if let bodyRange = requestStr.range(of: "\r\n\r\n") {
                let body = String(requestStr[bodyRange.upperBound...])
                handlePostRulesDelete(clientSocket, body: body)
            } else {
                sendJson(clientSocket, json: "{\"success\": false, \"error\": \"No body\"}", status: 400)
            }
        } else if method == "POST" && path == "/api/categorize" {
            if let bodyRange = requestStr.range(of: "\r\n\r\n") {
                let body = String(requestStr[bodyRange.upperBound...])
                handlePostCategorize(clientSocket, body: body)
            } else {
                sendJson(clientSocket, json: "{\"success\": false, \"error\": \"No body\"}", status: 400)
            }
        } else if method == "GET" && path == "/api/system-prompt" {
            serveApiSystemPrompt(clientSocket)
        } else if method == "POST" && path == "/api/system-prompt" {
            if let bodyRange = requestStr.range(of: "\r\n\r\n") {
                let body = String(requestStr[bodyRange.upperBound...])
                handlePostSystemPrompt(clientSocket, body: body)
            } else {
                sendJson(clientSocket, json: "{\"success\": false, \"error\": \"No body\"}", status: 400)
            }
        } else {
            sendResponse(clientSocket, body: "Not Found", contentType: "text/plain", status: 404)
        }
    }
    
    private func sendResponse(_ socket: Int32, body: String, contentType: String, status: Int = 200) {
        let statusStr = status == 200 ? "200 OK" : (status == 404 ? "404 Not Found" : "400 Bad Request")
        let bodyData = body.data(using: .utf8)!
        let headerLines = [
            "HTTP/1.1 \(statusStr)",
            "Content-Type: \(contentType); charset=utf-8",
            "Content-Length: \(bodyData.count)",
            "Access-Control-Allow-Origin: *",
            "Cache-Control: no-cache, no-store, must-revalidate",
            "Pragma: no-cache",
            "Expires: 0",
            "Connection: close",
            "",
            ""
        ]
        let headers = headerLines.joined(separator: "\r\n")
        let headersData = headers.data(using: .utf8)!
        var responseData = Data()
        responseData.append(headersData)
        responseData.append(bodyData)
        
        print("HTTP Server: sendResponse status=\(statusStr), headersLen=\(headersData.count), bodyLen=\(bodyData.count), totalToWrite=\(responseData.count)")
        
        responseData.withUnsafeBytes { ptr in
            guard let baseAddr = ptr.baseAddress else { return }
            var totalWritten = 0
            let totalLength = responseData.count
            while totalWritten < totalLength {
                let bytesWritten = write(socket, baseAddr + totalWritten, totalLength - totalWritten)
                if bytesWritten <= 0 {
                    print("HTTP Server: write failed at \(totalWritten)/\(totalLength), returned \(bytesWritten), error=\(errno)")
                    break
                }
                totalWritten += bytesWritten
            }
            print("HTTP Server: write complete, totalWritten=\(totalWritten)/\(totalLength)")
        }
    }
    
    private func sendJson(_ socket: Int32, json: String, status: Int = 200) {
        sendResponse(socket, body: json, contentType: "application/json", status: status)
    }
    
    private func serveDashboard(_ socket: Int32) {
        sendResponse(socket, body: dashboardHtml, contentType: "text/html")
    }
    
    private func serveApiStats(_ socket: Int32, dateStr: String, deviceStr: String) {
        let cleanedDate: String
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        if dateStr.isEmpty {
            cleanedDate = dateFormatter.string(from: Date())
        } else {
            cleanedDate = dateStr
        }
        
        let stats = db.getStatsForDate(dateStr: cleanedDate, device: deviceStr)
        let apps = db.getAppStatsForDate(dateStr: cleanedDate, device: deviceStr)
        let categories = db.getCategoryStatsForDate(dateStr: cleanedDate, device: deviceStr)
        let timeline = db.getEventsForDate(dateStr: cleanedDate, device: deviceStr)
        let focus = db.getFocusStatsForDate(dateStr: cleanedDate, device: deviceStr)
        
        var appJsonList: [String] = []
        for app in apps {
            appJsonList.append("{\"appName\": \"\(escapeJson(app.appName))\", \"duration\": \(app.duration), \"percentage\": \(app.percentage)}")
        }
        
        var catJsonList: [String] = []
        for (cat, dur) in categories {
            catJsonList.append("\"\(escapeJson(cat))\": \(dur)")
        }
        
        var timelineJsonList: [String] = []
        for event in timeline {
            timelineJsonList.append("""
            {
                "id": \(event.id),
                "appName": "\(escapeJson(event.appName))",
                "windowTitle": "\(escapeJson(event.windowTitle))",
                "startTime": "\(formatHour(event.startTime))",
                "duration": \(event.duration),
                "isIdle": \(event.isIdle ? "true" : "false"),
                "category": "\(escapeJson(event.category))"
            }
            """)
        }
        
        let jsonResponse = """
        {
            "date": "\(cleanedDate)",
            "totalActive": \(stats.totalActive),
            "totalIdle": \(stats.totalIdle),
            "focusedTime": \(focus.focused),
            "multitaskingTime": \(focus.multitasking),
            "appStats": [\(appJsonList.joined(separator: ","))],
            "categoryStats": {\(catJsonList.joined(separator: ","))},
            "timeline": [\(timelineJsonList.joined(separator: ","))]
        }
        """
        sendJson(socket, json: jsonResponse)
    }
    
    private func serveApiWeeklyStats(_ socket: Int32, dateStr: String, deviceStr: String) {
        let cleanedDate: String
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        if dateStr.isEmpty {
            cleanedDate = dateFormatter.string(from: Date())
        } else {
            cleanedDate = dateStr
        }
        
        let report = db.getWeeklyReport(relativeTo: cleanedDate, device: deviceStr)
        
        let dailyStats = report["dailyStats"] as? [[String: Any]] ?? []
        var dailyJsonList: [String] = []
        for stat in dailyStats {
            let d = stat["date"] as? String ?? ""
            let active = stat["active"] as? Double ?? 0.0
            let idle = stat["idle"] as? Double ?? 0.0
            let focused = stat["focused"] as? Double ?? 0.0
            let multitasking = stat["multitasking"] as? Double ?? 0.0
            dailyJsonList.append("""
            {
                "date": "\(d)",
                "active": \(active),
                "idle": \(idle),
                "focused": \(focused),
                "multitasking": \(multitasking)
            }
            """)
        }
        
        let categoryStats = report["categoryStats"] as? [String: Double] ?? [:]
        var catJsonList: [String] = []
        for (cat, dur) in categoryStats {
            catJsonList.append("\"\(escapeJson(cat))\": \(dur)")
        }
        
        let thisWeek = report["thisWeek"] as? [String: Double] ?? [:]
        let priorWeek = report["priorWeek"] as? [String: Double] ?? [:]
        
        let thisWeekActive = thisWeek["active"] ?? 0.0
        let thisWeekIdle = thisWeek["idle"] ?? 0.0
        let thisWeekFocused = thisWeek["focused"] ?? 0.0
        let thisWeekMultitasking = thisWeek["multitasking"] ?? 0.0
        
        let priorWeekActive = priorWeek["active"] ?? 0.0
        let priorWeekIdle = priorWeek["idle"] ?? 0.0
        let priorWeekFocused = priorWeek["focused"] ?? 0.0
        let priorWeekMultitasking = priorWeek["multitasking"] ?? 0.0
        
        let jsonResponse = """
        {
            "date": "\(cleanedDate)",
            "dailyStats": [\(dailyJsonList.joined(separator: ","))],
            "categoryStats": {\(catJsonList.joined(separator: ","))},
            "thisWeek": {
                "active": \(thisWeekActive),
                "idle": \(thisWeekIdle),
                "focused": \(thisWeekFocused),
                "multitasking": \(thisWeekMultitasking)
            },
            "priorWeek": {
                "active": \(priorWeekActive),
                "idle": \(priorWeekIdle),
                "focused": \(priorWeekFocused),
                "multitasking": \(priorWeekMultitasking)
            }
        }
        """
        sendJson(socket, json: jsonResponse)
    }
    
    private func serveApiRules(_ socket: Int32) {
        let rules = db.getAllRules()
        var rulesJsonList: [String] = []
        for rule in rules {
            let id = rule["id"] as? Int ?? 0
            let appName = rule["appName"] as? String ?? ""
            let titlePattern = rule["titlePattern"] as? String ?? ""
            let category = rule["category"] as? String ?? ""
            rulesJsonList.append("""
            {
                "id": \(id),
                "appName": "\(escapeJson(appName))",
                "titlePattern": "\(escapeJson(titlePattern))",
                "category": "\(escapeJson(category))"
            }
            """)
        }
        let jsonResponse = "[\(rulesJsonList.joined(separator: ","))]"
        sendJson(socket, json: jsonResponse)
    }
    
    private func serveApiExport(_ socket: Int32, dateStr: String, deviceStr: String) {
        let cleanedDate: String
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        if dateStr.isEmpty {
            cleanedDate = dateFormatter.string(from: Date())
        } else {
            cleanedDate = dateStr
        }
        
        let events = db.getEventsForDate(dateStr: cleanedDate, device: deviceStr)
        var eventsJsonList: [String] = []
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        for event in events {
            eventsJsonList.append("""
            {
                "id": \(event.id),
                "appName": "\(escapeJson(event.appName))",
                "windowTitle": "\(escapeJson(event.windowTitle))",
                "startTime": "\(timeFormatter.string(from: event.startTime))",
                "endTime": "\(timeFormatter.string(from: event.endTime))",
                "duration": \(event.duration),
                "isIdle": \(event.isIdle ? "true" : "false"),
                "category": "\(escapeJson(event.category))"
            }
            """)
        }
        let jsonResponse = "[\(eventsJsonList.joined(separator: ","))]"
        sendJson(socket, json: jsonResponse)
    }
    
    // Auto-Start (Launch Agent) helper methods
    static func isLaunchAtLoginEnabled() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "LaunchAtLoginEnabled") == nil {
            return true // Default to true on first run
        }
        return defaults.bool(forKey: "LaunchAtLoginEnabled")
    }
    
    @discardableResult
    static func setLaunchAtLogin(enabled: Bool) -> Bool {
        UserDefaults.standard.set(enabled, forKey: "LaunchAtLoginEnabled")
        
        let plistPath = (NSString(string: "~").expandingTildeInPath as NSString).appendingPathComponent("Library/LaunchAgents/net.mitthu.Mitthu.plist")
        let fileManager = FileManager.default
        
        // Unload the agent first to ensure clean state if it exists
        if fileManager.fileExists(atPath: plistPath) {
            let unloadProcess = Process()
            unloadProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            unloadProcess.arguments = ["unload", plistPath]
            try? unloadProcess.run()
            unloadProcess.waitUntilExit()
        }
        
        if !enabled {
            if fileManager.fileExists(atPath: plistPath) {
                try? fileManager.removeItem(atPath: plistPath)
            }
            return true
        }
        
        guard let execPath = Bundle.main.executablePath else { return false }
        
        let plistDict: [String: Any] = [
            "Label": "net.mitthu.Mitthu",
            "ProgramArguments": [execPath],
            "RunAtLoad": true,
            "KeepAlive": false
        ]
        
        let plistData = try? PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
        if let data = plistData {
            let folderPath = (plistPath as NSString).deletingLastPathComponent
            if !fileManager.fileExists(atPath: folderPath) {
                try? fileManager.createDirectory(atPath: folderPath, withIntermediateDirectories: true, attributes: nil)
            }
            do {
                try data.write(to: URL(fileURLWithPath: plistPath))
                
                // Load the agent immediately so launchd registers it
                let loadProcess = Process()
                loadProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                loadProcess.arguments = ["load", "-w", plistPath]
                try? loadProcess.run()
                loadProcess.waitUntilExit()
                
                return true
            } catch {
                print("Mitthu: Failed to write autostart plist: \(error)")
                return false
            }
        }
        return false
    }
    
    private func serveApiAutoStart(_ socket: Int32) {
        let enabled = HttpServer.isLaunchAtLoginEnabled()
        sendJson(socket, json: "{\"enabled\": \(enabled)}")
    }
    
    private func handlePostAutoStart(_ socket: Int32, body: String) {
        guard let data = body.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let enabled = json["enabled"] as? Bool else {
            sendJson(socket, json: "{\"success\": false, \"error\": \"Missing or invalid 'enabled' parameter\"}", status: 400)
            return
        }
        
        let success = HttpServer.setLaunchAtLogin(enabled: enabled)
        sendJson(socket, json: "{\"success\": \(success)}")
    }
    
    private func serveApiSystemPrompt(_ socket: Int32) {
        let currentDir = FileManager.default.currentDirectoryPath
        let instructionsURL = URL(fileURLWithPath: currentDir).appendingPathComponent("instructions.md")
        var systemPrompt = "You are Mitthu Assistant, a privacy-first local AI productivity expert. You analyze screen time, categorize activities, identify distractions, and suggest learning strategies like Spaced Repetition, Active Recall, and the Feynman Technique. Always format your responses in a clean, human-friendly, point-wise (bulleted) structure. Avoid long paragraphs and make it easy to scan at a glance."
        
        if FileManager.default.fileExists(atPath: instructionsURL.path),
           let content = try? String(contentsOf: instructionsURL, encoding: .utf8) {
            systemPrompt = content
        }
        
        let jsonResponse = "{\"prompt\": \"\(escapeJson(systemPrompt))\"}"
        sendJson(socket, json: jsonResponse)
    }
    
    private func handlePostSystemPrompt(_ socket: Int32, body: String) {
        guard let data = body.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else {
            sendJson(socket, json: "{\"success\": false, \"error\": \"Invalid encoding\"}", status: 400)
            return
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let prompt = json["prompt"] as? String else {
            sendJson(socket, json: "{\"success\": false, \"error\": \"Could not parse prompt\"}", status: 400)
            return
        }
        
        let currentDir = FileManager.default.currentDirectoryPath
        let instructionsURL = URL(fileURLWithPath: currentDir).appendingPathComponent("instructions.md")
        
        do {
            try prompt.write(to: instructionsURL, atomically: true, encoding: .utf8)
            print("Mitthu Server: Updated instructions.md on disk.")
            sendJson(socket, json: "{\"success\": true}")
        } catch {
            print("Mitthu Server Error: Could not write to instructions.md: \(error.localizedDescription)")
            sendJson(socket, json: "{\"success\": false, \"error\": \"Could not write to file\"}", status: 500)
        }
    }
    
    private func handlePostRulesDelete(_ socket: Int32, body: String) {
        guard let data = body.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else {
            sendJson(socket, json: "{\"success\": false, \"error\": \"Invalid encoding\"}", status: 400)
            return
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            sendJson(socket, json: "{\"success\": false, \"error\": \"Could not parse JSON\"}", status: 400)
            return
        }
        
        if let id = json["id"] as? Int {
            db.deleteRule(id: id)
            sendJson(socket, json: "{\"success\": true}")
        } else {
            sendJson(socket, json: "{\"success\": false, \"error\": \"Missing id\"}", status: 400)
        }
    }
    
    private func handlePostCategorize(_ socket: Int32, body: String) {
        guard let data = body.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else {
            sendJson(socket, json: "{\"success\": false, \"error\": \"Invalid encoding\"}", status: 400)
            return
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            sendJson(socket, json: "{\"success\": false, \"error\": \"Could not parse JSON\"}", status: 400)
            return
        }
        
        var parsedEventId: Int? = nil
        if let idInt = json["eventId"] as? Int {
            parsedEventId = idInt
        } else if let idNum = json["eventId"] as? NSNumber {
            parsedEventId = idNum.intValue
        } else if let idStr = json["eventId"] as? String, let idInt = Int(idStr) {
            parsedEventId = idInt
        }
        
        if let eventId = parsedEventId, let category = json["category"] as? String {
            print("Mitthu Server: Updating event category eventId=\(eventId), category=\(category)")
            db.updateEventCategory(eventId: eventId, category: category)
            sendJson(socket, json: "{\"success\": true}")
            return
        }
        
        if let category = json["category"] as? String {
            let appName = json["appName"] as? String ?? ""
            let titlePattern = json["titlePattern"] as? String ?? ""
            print("Mitthu Server: Adding rule appName=\(appName), titlePattern=\(titlePattern), category=\(category)")
            db.addRule(appName: appName, titlePattern: titlePattern, category: category)
            sendJson(socket, json: "{\"success\": true}")
            return
        }
        
        sendJson(socket, json: "{\"success\": false, \"error\": \"Missing params\"}", status: 400)
    }

    
    private func escapeJson(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
    
    private func formatHour(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    // Embedded HTML Dashboard Code
    private var dashboardHtml: String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Mitthu — Dashboard</title>
            <script src="https://cdn.tailwindcss.com"></script>
            <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
            <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;700&family=Inter:wght@300;400;500;600&display=swap" rel="stylesheet">
            <style>
                body {
                    font-family: 'Inter', sans-serif;
                }
                h1, h2, h3, .font-heading {
                    font-family: 'Outfit', sans-serif;
                }
                .glass-card {
                    background: rgba(24, 24, 27, 0.65);
                    backdrop-filter: blur(12px);
                    -webkit-backdrop-filter: blur(12px);
                    border: 1px solid rgba(63, 63, 70, 0.4);
                }
            </style>
        </head>
        <body class="bg-black text-zinc-200 min-h-screen pb-12">
            <!-- Navigation Header -->
            <header class="border-b border-zinc-800 bg-zinc-950/80 backdrop-blur sticky top-0 z-50">
                <div class="max-w-7xl mx-auto px-6 h-16 flex items-center justify-between">
                    <div class="flex items-center space-x-3">
                        <div class="w-8 h-8 rounded-lg bg-gradient-to-tr from-purple-600 to-indigo-600 flex items-center justify-center shadow-lg shadow-purple-500/20">
                            <span class="text-lg">🦜</span>
                        </div>
                        <span class="font-heading text-lg font-bold tracking-tight text-white">Mitthu</span>
                        <span class="text-xs px-2 py-0.5 rounded bg-zinc-800 text-zinc-400 border border-zinc-700">macOS Native v1.0</span>
                    </div>
                    
                    <!-- Date Picker Actions -->
                    <div class="flex items-center space-x-3">
                        <button onclick="navigateDate(-1)" class="p-2 rounded-lg bg-zinc-900 border border-zinc-800 hover:bg-zinc-800 hover:border-zinc-700 transition">
                            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/></svg>
                        </button>
                        <input type="date" id="date-picker" onchange="dateChanged()" class="bg-zinc-900 border border-zinc-800 rounded-lg px-3 py-1.5 text-sm text-white focus:outline-none focus:ring-2 focus:ring-purple-600">
                        <button onclick="navigateDate(1)" class="p-2 rounded-lg bg-zinc-900 border border-zinc-800 hover:bg-zinc-800 hover:border-zinc-700 transition">
                            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/></svg>
                        </button>
                        <button onclick="setToday()" class="text-xs px-3 py-2 rounded-lg bg-purple-600 hover:bg-purple-500 font-semibold text-white transition">Today</button>
                    </div>
                </div>
            </header>

            <main class="max-w-7xl mx-auto px-6 mt-8 space-y-8">
                <!-- Navigation Tabs -->
                <div class="flex border-b border-zinc-800">
                    <button id="btn-tab-dashboard" onclick="showTab('dashboard')" class="tab-btn px-6 py-3 font-heading text-sm font-semibold border-b-2 border-purple-500 text-white bg-zinc-900/50 transition">Daily Dashboard</button>
                    <button id="btn-tab-weekly" onclick="showTab('weekly')" class="tab-btn px-6 py-3 font-heading text-sm font-semibold border-b-2 border-transparent text-zinc-400 hover:text-white transition">Weekly Report</button>
                    <button id="btn-tab-settings" onclick="showTab('settings')" class="tab-btn px-6 py-3 font-heading text-sm font-semibold border-b-2 border-transparent text-zinc-400 hover:text-white transition">Rules & Settings</button>
                    <button id="btn-tab-ai" onclick="showTab('ai')" class="tab-btn px-6 py-3 font-heading text-sm font-semibold border-b-2 border-transparent text-zinc-400 hover:text-white transition">Local AI Chat</button>
                </div>

                <!-- TAB 1: DAILY DASHBOARD -->
                <div id="tab-dashboard" class="tab-content space-y-8">
                    <!-- Summary Metrics -->
                    <div class="grid grid-cols-1 md:grid-cols-4 gap-6">
                        <div class="glass-card rounded-2xl p-6 relative overflow-hidden">
                            <h3 class="text-xs font-bold text-zinc-400 tracking-wider uppercase">Active Screen Time</h3>
                            <p class="text-3xl font-heading font-bold text-blue-400 mt-2" id="stat-active">0h 0m</p>
                            <span class="text-xs text-zinc-500 mt-1 block">Focused active screen time.</span>
                        </div>
                        <div class="glass-card rounded-2xl p-6 relative overflow-hidden">
                            <h3 class="text-xs font-bold text-zinc-400 tracking-wider uppercase">Away (Idle)</h3>
                            <p class="text-3xl font-heading font-bold text-zinc-400 mt-2" id="stat-idle">0h 0m</p>
                            <span class="text-xs text-zinc-500 mt-1 block">Time spent away from keyboard.</span>
                        </div>
                        <div class="glass-card rounded-2xl p-6 relative overflow-hidden">
                            <h3 class="text-xs font-bold text-zinc-400 tracking-wider uppercase">Focus vs Multitasking</h3>
                            <p class="text-3xl font-heading font-bold text-emerald-400 mt-2" id="stat-focus-score">0%</p>
                            <span class="text-xs text-zinc-500 mt-1 block" id="stat-focus-sub">Focus: 0m | Multitask: 0m</span>
                        </div>
                        <div class="glass-card rounded-2xl p-6 relative overflow-hidden">
                            <h3 class="text-xs font-bold text-zinc-400 tracking-wider uppercase">Tracked Events</h3>
                            <p class="text-3xl font-heading font-bold text-purple-400 mt-2" id="stat-events">0</p>
                            <span class="text-xs text-zinc-500 mt-1 block">Activity switches logged today.</span>
                        </div>
                    </div>

                    <!-- Charts Section -->
                    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
                        <div class="glass-card rounded-2xl p-6">
                            <h2 class="font-heading text-lg font-bold text-white mb-4">Category Distribution</h2>
                            <div class="h-64 flex items-center justify-center">
                                <canvas id="categoryChart"></canvas>
                            </div>
                        </div>
                        <div class="glass-card rounded-2xl p-6">
                            <h2 class="font-heading text-lg font-bold text-white mb-4">Top Applications</h2>
                            <div class="h-64">
                                <canvas id="appsChart"></canvas>
                            </div>
                        </div>
                    </div>

                    <!-- Quick Rule Section -->
                    <div class="glass-card rounded-2xl p-6">
                        <h2 class="font-heading text-lg font-bold text-white mb-2">Create Categorization Rule</h2>
                        <p class="text-xs text-zinc-400 mb-4">Automatically tag application titles. Group related study portals and videos (e.g. Maths YouTube video and portal) under the same category to count them as focus rather than multitasking!</p>
                        <form id="rule-form" onsubmit="submitRule(event)" class="grid grid-cols-1 md:grid-cols-4 gap-4">
                            <div>
                                <label class="block text-xs font-bold text-zinc-400 uppercase mb-1">Application Name</label>
                                <input type="text" id="rule-app" placeholder="e.g., Safari" class="w-full bg-zinc-900 border border-zinc-800 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:ring-1 focus:ring-purple-600">
                            </div>
                            <div>
                                <label class="block text-xs font-bold text-zinc-400 uppercase mb-1">Window Title Contains</label>
                                <input type="text" id="rule-title" placeholder="e.g., YouTube" class="w-full bg-zinc-900 border border-zinc-800 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:ring-1 focus:ring-purple-600">
                            </div>
                            <div>
                                <label class="block text-xs font-bold text-zinc-400 uppercase mb-1">Category / Topic</label>
                                <input list="common-categories" id="rule-category" placeholder="e.g., Maths Study" class="w-full bg-zinc-900 border border-zinc-800 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:ring-1 focus:ring-purple-600">
                                <datalist id="common-categories">
                                    <option value="Study">
                                    <option value="Work">
                                    <option value="Entertainment">
                                    <option value="Social">
                                    <option value="Maths Study">
                                    <option value="Coding">
                                </datalist>
                            </div>
                            <div class="flex items-end">
                                <button type="submit" class="w-full bg-purple-600 hover:bg-purple-500 py-2 rounded-lg text-sm font-semibold text-white transition">Apply Rule</button>
                            </div>
                        </form>
                    </div>

                    <!-- Timeline Log -->
                    <div class="glass-card rounded-2xl overflow-hidden">
                        <div class="p-6 border-b border-zinc-800">
                            <h2 class="font-heading text-lg font-bold text-white">Daily Timeline Log</h2>
                        </div>
                        <div class="overflow-x-auto">
                            <table class="w-full text-left border-collapse">
                                <thead class="border-b border-zinc-800 bg-zinc-900/40 text-xs font-bold text-zinc-400 uppercase select-none">
                                    <tr>
                                        <th id="th-time" data-label="Time" onclick="sortBy('time')" class="py-3 px-6 cursor-pointer hover:text-white transition">Time ▼</th>
                                        <th id="th-appName" data-label="Application" onclick="sortBy('appName')" class="py-3 px-6 cursor-pointer hover:text-white transition">Application</th>
                                        <th class="py-3 px-6">Window Title</th>
                                        <th id="th-duration" data-label="Duration" onclick="sortBy('duration')" class="py-3 px-6 cursor-pointer hover:text-white transition">Duration</th>
                                        <th id="th-category" data-label="Category" onclick="sortBy('category')" class="py-3 px-6 cursor-pointer hover:text-white transition">Category</th>
                                    </tr>
                                </thead>
                                <tbody id="timeline-body" class="divide-y divide-zinc-800/50 text-sm">
                                    <!-- Loaded via JS -->
                                </tbody>
                            </table>
                        </div>
                    </div>
                </div>

                <!-- TAB 2: WEEKLY REPORT -->
                <div id="tab-weekly" class="tab-content hidden space-y-8">
                    <!-- Weekly Metrics Grid -->
                    <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
                        <div class="glass-card rounded-2xl p-6 relative overflow-hidden">
                            <h3 class="text-xs font-bold text-zinc-400 tracking-wider uppercase">Weekly Active Time</h3>
                            <p class="text-3xl font-heading font-bold text-blue-400 mt-2" id="weekly-active">0h 0m</p>
                            <span class="text-xs text-zinc-500 mt-1 block" id="weekly-active-compare">vs. Last Week: 0h</span>
                        </div>
                        <div class="glass-card rounded-2xl p-6 relative overflow-hidden">
                            <h3 class="text-xs font-bold text-zinc-400 tracking-wider uppercase">Weekly Focus Score</h3>
                            <p class="text-3xl font-heading font-bold text-emerald-400 mt-2" id="weekly-focus">0%</p>
                            <span class="text-xs text-zinc-500 mt-1 block" id="weekly-focus-compare">vs. Last Week: 0%</span>
                        </div>
                        <div class="glass-card rounded-2xl p-6 relative overflow-hidden">
                            <h3 class="text-xs font-bold text-zinc-400 tracking-wider uppercase">Weekly Idle Time</h3>
                            <p class="text-3xl font-heading font-bold text-zinc-400 mt-2" id="weekly-idle">0h 0m</p>
                            <span class="text-xs text-zinc-500 mt-1 block" id="weekly-idle-compare">vs. Last Week: 0h</span>
                        </div>
                    </div>

                    <!-- Weekly Charts Section -->
                    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
                        <div class="glass-card rounded-2xl p-6">
                            <h2 class="font-heading text-lg font-bold text-white mb-4">Focus vs Multitasking Trend</h2>
                            <div class="h-64">
                                <canvas id="weeklyFocusChart"></canvas>
                            </div>
                        </div>
                        <div class="glass-card rounded-2xl p-6">
                            <h2 class="font-heading text-lg font-bold text-white mb-4">Daily Activity Patterns</h2>
                            <div class="h-64">
                                <canvas id="weeklyTrendChart"></canvas>
                            </div>
                        </div>
                    </div>

                    <div class="glass-card rounded-2xl p-6">
                        <h2 class="font-heading text-lg font-bold text-white mb-4">Weekly Category Summary</h2>
                        <div class="h-64 flex items-center justify-center">
                            <canvas id="weeklyCategoryChart"></canvas>
                        </div>
                    </div>
                </div>

                <!-- TAB 3: RULES & SETTINGS -->
                <div id="tab-settings" class="tab-content hidden space-y-8">
                    <!-- Rule Creation Form -->
                    <div class="glass-card rounded-2xl p-6">
                        <h2 class="font-heading text-lg font-bold text-white mb-2">Add New Custom Rule</h2>
                        <p class="text-xs text-zinc-400 mb-4">Create classification rules. Setting the same Category name for both research portals and learning videos maps them under a single task/topic. This stops them from being flagged as multitasking context-switches!</p>
                        <form id="settings-rule-form" onsubmit="submitSettingsRule(event)" class="grid grid-cols-1 md:grid-cols-4 gap-4">
                            <div>
                                <label class="block text-xs font-bold text-zinc-400 uppercase mb-1">Application Name</label>
                                <input type="text" id="set-rule-app" placeholder="e.g., Google Chrome" class="w-full bg-zinc-900 border border-zinc-800 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:ring-1 focus:ring-purple-600">
                            </div>
                            <div>
                                <label class="block text-xs font-bold text-zinc-400 uppercase mb-1">Window Title Contains</label>
                                <input type="text" id="set-rule-title" placeholder="e.g., mathsportal.com" class="w-full bg-zinc-900 border border-zinc-800 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:ring-1 focus:ring-purple-600">
                            </div>
                            <div>
                                <label class="block text-xs font-bold text-zinc-400 uppercase mb-1">Category / Topic</label>
                                <input list="common-categories" id="set-rule-category" placeholder="e.g., Maths Study" class="w-full bg-zinc-900 border border-zinc-800 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:ring-1 focus:ring-purple-600">
                            </div>
                            <div class="flex items-end">
                                <button type="submit" class="w-full bg-purple-600 hover:bg-purple-500 py-2 rounded-lg text-sm font-semibold text-white transition">Create Rule</button>
                            </div>
                        </form>
                    </div>

                    <!-- Rules List -->
                    <div class="glass-card rounded-2xl overflow-hidden">
                        <div class="p-6 border-b border-zinc-800">
                            <h2 class="font-heading text-lg font-bold text-white">Active Categorization Rules</h2>
                        </div>
                        <div class="overflow-x-auto">
                            <table class="w-full text-left border-collapse">
                                <thead>
                                    <tr class="border-b border-zinc-800 bg-zinc-900/40 text-xs font-bold text-zinc-400 uppercase">
                                        <th class="py-3 px-6">Application</th>
                                        <th class="py-3 px-6">Title Contains Pattern</th>
                                        <th class="py-3 px-6">Assigned Category / Topic</th>
                                        <th class="py-3 px-6 text-right">Action</th>
                                    </tr>
                                </thead>
                                <tbody id="rules-list-body" class="divide-y divide-zinc-800/50 text-sm">
                                    <!-- Loaded via JS -->
                                </tbody>
                            </table>
                        </div>
                    </div>

                    <!-- System Preferences -->
                    <div class="glass-card rounded-2xl p-6">
                        <h2 class="font-heading text-lg font-bold text-white mb-2">System Preferences</h2>
                        <p class="text-xs text-zinc-400 mb-4">Manage system startup behavior for Mitthu.</p>
                        <div class="flex items-center gap-3">
                            <input type="checkbox" id="autostart-toggle" onchange="toggleAutoStart(this)" class="w-4 h-4 rounded text-purple-600 focus:ring-purple-600 focus:ring-opacity-25 border-zinc-800 bg-zinc-950 cursor-pointer">
                            <label for="autostart-toggle" class="text-sm font-semibold text-zinc-200 cursor-pointer select-none">Start Mitthu automatically on system startup</label>
                        </div>
                    </div>

                    <!-- Data Export & Insights -->
                    <div class="glass-card rounded-2xl p-6">
                        <h2 class="font-heading text-lg font-bold text-white mb-2">Export Data for AI Insights</h2>
                        <p class="text-xs text-zinc-400 mb-4">Download your tracked window activity logs for the currently selected day in raw JSON format to feed into ChatGPT, Claude, or any local LLM to get custom productivity analysis and focus reports.</p>
                        <div class="flex flex-wrap gap-4">
                            <button onclick="exportRawData()" class="bg-purple-600 hover:bg-purple-500 py-2.5 px-6 rounded-lg text-sm font-semibold text-white transition flex items-center gap-2">
                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"></path>
                                </svg>
                                Export Selected Day's JSON
                            </button>
                        </div>
                    </div>
                </div>

                <!-- TAB 4: LOCAL AI CHAT -->
                <div id="tab-ai" class="tab-content hidden space-y-8">
                    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6 items-start">
                        <!-- Left Panel: AI Configuration & Context -->
                        <div class="lg:col-span-1 space-y-6">
                            <!-- LLM Connection Settings -->
                            <div class="glass-card rounded-2xl p-6 space-y-4">
                                <h2 class="font-heading text-lg font-bold text-white flex items-center gap-2">
                                    <svg class="w-5 h-5 text-purple-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"/><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/></svg>
                                    Local LLM Settings
                                </h2>
                                <div>
                                    <label class="block text-xs font-bold text-zinc-400 uppercase mb-1">API Endpoint</label>
                                    <input type="text" id="ai-endpoint" value="http://localhost:11434/v1/chat/completions" placeholder="e.g., http://localhost:11434/v1/chat/completions" class="w-full bg-zinc-900 border border-zinc-800 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:ring-1 focus:ring-purple-600 font-mono">
                                    <span class="text-[10px] text-zinc-500 mt-1 block">Ollama: /v1/chat/completions or LM Studio: port 1234</span>
                                </div>
                                <div>
                                    <label class="block text-xs font-bold text-zinc-400 uppercase mb-1">Model Name</label>
                                    <input type="text" id="ai-model" value="llama3" placeholder="e.g., llama3, mistral, qwen2.5:14b" class="w-full bg-zinc-900 border border-zinc-800 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:ring-1 focus:ring-purple-600 font-mono">
                                </div>
                                <div>
                                    <label class="block text-xs font-bold text-zinc-400 uppercase mb-1">System Prompt</label>
                                    <textarea id="ai-system-prompt" rows="5" class="w-full bg-zinc-900 border border-zinc-800 rounded-lg px-3 py-2 text-xs text-white focus:outline-none focus:ring-1 focus:ring-purple-600 font-mono resize-y" placeholder="System instructions for the AI assistant..."></textarea>
                                </div>
                                <button type="button" onclick="saveAISettings()" class="w-full bg-zinc-800 hover:bg-zinc-700 py-2 rounded-lg text-xs font-semibold text-white transition border border-zinc-700">Save Configuration</button>
                            </div>

                            <!-- Context Ingestion Settings -->
                            <div class="glass-card rounded-2xl p-6 space-y-4">
                                <h2 class="font-heading text-lg font-bold text-white flex items-center gap-2">
                                    <svg class="w-5 h-5 text-indigo-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/></svg>
                                    Daily Data Context
                                </h2>
                                <p class="text-xs text-zinc-400 leading-relaxed">
                                    Choose what screen stats to inject into the model's context for <span class="current-date-display font-semibold text-purple-400">Today</span>.
                                </p>
                                <div class="space-y-3">
                                    <div class="flex items-center gap-3">
                                        <input type="checkbox" id="ai-ctx-stats" checked class="w-4 h-4 rounded text-purple-600 focus:ring-purple-600 focus:ring-opacity-25 border-zinc-800 bg-zinc-950 cursor-pointer">
                                        <label for="ai-ctx-stats" class="text-xs font-semibold text-zinc-200 cursor-pointer select-none">Include Screen Time & App Totals</label>
                                    </div>
                                    <div class="flex items-center gap-3">
                                        <input type="checkbox" id="ai-ctx-timeline" checked class="w-4 h-4 rounded text-purple-600 focus:ring-purple-600 focus:ring-opacity-25 border-zinc-800 bg-zinc-950 cursor-pointer">
                                        <label for="ai-ctx-timeline" class="text-xs font-semibold text-zinc-200 cursor-pointer select-none">Include Screen Event Logs</label>
                                    </div>
                                    <div class="bg-purple-950/20 border border-purple-900/40 rounded-xl p-3">
                                        <p class="text-[10px] text-purple-300 leading-normal">
                                            💡 <strong>Smart Filtering:</strong> Timeline logs are compressed client-side. We group duplicate adjacent events and filter out events shorter than 30s. This reduces the payload from 15,000+ tokens to ~700 tokens, keeping it light for your 12B model!
                                        </p>
                                    </div>
                                </div>
                            </div>

                            <!-- Quick Action Buttons -->
                            <div class="glass-card rounded-2xl p-6 space-y-4">
                                <h2 class="font-heading text-lg font-bold text-white flex items-center gap-2">
                                    <svg class="w-5 h-5 text-emerald-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"/></svg>
                                    One-Click Insights
                                </h2>
                                <div class="space-y-2">
                                    <button type="button" onclick="triggerQuickAction('summary')" class="w-full bg-gradient-to-r from-purple-600 to-indigo-600 hover:from-purple-500 hover:to-indigo-500 py-2.5 px-4 rounded-xl text-xs font-bold text-white transition shadow-lg shadow-purple-500/10 flex items-center justify-center gap-2">
                                        ✨ Summarize Today's Activity
                                    </button>
                                    <button type="button" onclick="triggerQuickAction('distractions')" class="w-full bg-zinc-800 hover:bg-zinc-750 py-2.5 px-4 rounded-xl text-xs font-bold text-zinc-200 transition border border-zinc-700 flex items-center justify-center gap-2">
                                        🔍 Identify Distractions
                                    </button>
                                    <button type="button" onclick="triggerQuickAction('lifestyle')" class="w-full bg-zinc-800 hover:bg-zinc-750 py-2.5 px-4 rounded-xl text-xs font-bold text-zinc-200 transition border border-zinc-700 flex items-center justify-center gap-2">
                                        🧠 Mnemonic Learning Tips
                                    </button>
                                </div>
                            </div>
                        </div>

                        <!-- Right Panel: Conversation -->
                        <div class="lg:col-span-2 glass-card rounded-2xl flex flex-col h-[650px] relative overflow-hidden">
                            <!-- Chat Header -->
                            <div class="p-4 border-b border-zinc-800 bg-zinc-950/40 flex items-center justify-between">
                                <div class="flex items-center space-x-3">
                                    <div class="w-3 h-3 rounded-full bg-green-500 animate-pulse"></div>
                                    <div>
                                        <h3 class="font-heading font-semibold text-white text-sm">Local Assistant</h3>
                                        <p class="text-[10px] text-zinc-400">Direct connection via local API</p>
                                    </div>
                                </div>
                                <button type="button" onclick="clearChatLog()" class="text-xs text-zinc-400 hover:text-white px-2 py-1 rounded hover:bg-zinc-800 transition">Clear Chat</button>
                            </div>

                            <!-- Messages Area -->
                            <div id="ai-chat-log" class="flex-1 overflow-y-auto p-6 space-y-4">
                                <!-- Welcome Message -->
                                <div id="chat-welcome-card" class="max-w-md mx-auto text-center space-y-4 py-8 select-none">
                                    <div class="w-12 h-12 rounded-2xl bg-gradient-to-tr from-purple-600 to-indigo-600 flex items-center justify-center mx-auto shadow-lg shadow-purple-500/20">
                                        <span class="text-2xl">🦜</span>
                                    </div>
                                    <h4 class="font-heading font-semibold text-white text-base">Local AI Brain Sync</h4>
                                    <p class="text-xs text-zinc-400 leading-relaxed">
                                        Ask questions about your daily screen behavior, get focus insights, or let the AI analyze your timeline log. Ensure your local LLM (Ollama or LM Studio) is running on localhost!
                                    </p>
                                    <div class="text-[10px] text-zinc-500 border border-zinc-800 rounded-lg p-2.5 bg-zinc-950/40 max-w-sm mx-auto text-left leading-normal">
                                        <strong>Trouble connecting?</strong> If requests fail, verify CORS is allowed. For Ollama on macOS, run: <code class="text-purple-300 font-mono text-[9px]">OLLAMA_ORIGINS="*" ollama serve</code>
                                    </div>
                                </div>
                            </div>

                            <!-- Chat Input -->
                            <div class="p-4 border-t border-zinc-800 bg-zinc-950/30">
                                <form id="ai-input-form" onsubmit="submitChatMessage(event)" class="flex gap-2">
                                    <input type="text" id="ai-user-prompt" placeholder="Ask about today's focus score, how you spent your time, or general questions..." class="flex-1 bg-zinc-900 border border-zinc-800 rounded-xl px-4 py-3 text-sm text-white focus:outline-none focus:ring-2 focus:ring-purple-600 placeholder-zinc-500">
                                    <button type="submit" id="ai-send-btn" class="bg-purple-600 hover:bg-purple-500 text-white font-semibold text-sm px-5 rounded-xl transition flex items-center gap-1.5 shadow-lg shadow-purple-500/10">
                                        Send
                                        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 19l9-2-9-18-9 18 9-2zm0 0v-8"/></svg>
                                    </button>
                                </form>
                            </div>
                        </div>
                    </div>
                </div>
            </main>

            <script>
                // Helper to format date as local YYYY-MM-DD
                function formatLocalDate(date) {
                    const year = date.getFullYear();
                    const month = String(date.getMonth() + 1).padStart(2, '0');
                    const day = String(date.getDate()).padStart(2, '0');
                    return `${year}-${month}-${day}`;
                }

                // Global category config
                let availableCategories = ["Study", "Work", "Entertainment", "Social", "Uncategorized"];
                let currentSortKey = 'time';
                let currentSortOrder = 'desc';
                let currentEvents = [];

                function getCategoryColor(category) {
                    const colors = {
                        'Study': '#22c55e',         // Bright green (per user request)
                        'Work': '#3b82f6',          // Blue
                        'Entertainment': '#ec4899',   // Pink
                        'Social': '#f97316',        // Orange
                        'Uncategorized': '#64748b',   // Slate
                        'No Active Data': '#27272a',
                        'No Data': '#27272a'
                    };
                    if (colors[category]) {
                        return colors[category];
                    }
                    // Generate HSL color dynamically for custom categories so they look pretty
                    let hash = 0;
                    for (let i = 0; i < category.length; i++) {
                        hash = category.charCodeAt(i) + ((hash << 5) - hash);
                    }
                    const h = Math.abs(hash % 360);
                    return `hsl(${h}, 70%, 55%)`;
                }

                // App State
                let currentDate = formatLocalDate(new Date());
                let currentTab = 'dashboard';
                let currentDevice = 'Mac';
                
                // Chart Instances
                let categoryChartInstance = null;
                let appsChartInstance = null;
                let weeklyTrendChartInstance = null;
                let weeklyCategoryChartInstance = null;
                let weeklyFocusChartInstance = null;

                document.getElementById('date-picker').value = currentDate;

                // Load initial dashboard stats
                loadData();

                function sortBy(key) {
                    if (currentSortKey === key) {
                        currentSortOrder = currentSortOrder === 'asc' ? 'desc' : 'asc';
                    } else {
                        currentSortKey = key;
                        currentSortOrder = 'asc';
                    }
                    updateHeaderSortIcons();
                    renderTimeline(currentEvents);
                }

                function updateHeaderSortIcons() {
                    const keys = ['time', 'appName', 'duration', 'category'];
                    keys.forEach(k => {
                        const th = document.getElementById(`th-${k}`);
                        if (!th) return;
                        let text = th.dataset.label;
                        if (currentSortKey === k) {
                            text += currentSortOrder === 'asc' ? ' ▲' : ' ▼';
                        }
                        th.innerText = text;
                    });
                }

                function showTab(tabName) {
                    currentTab = tabName;
                    document.querySelectorAll('.tab-content').forEach(el => el.classList.add('hidden'));
                    document.getElementById(`tab-${tabName}`).classList.remove('hidden');
                    
                    document.querySelectorAll('.tab-btn').forEach(btn => {
                        btn.classList.remove('text-white', 'border-purple-500', 'bg-zinc-900/50');
                        btn.classList.add('text-zinc-400', 'border-transparent');
                    });
                    
                    const activeBtn = document.getElementById(`btn-tab-${tabName}`);
                    activeBtn.classList.remove('text-zinc-400', 'border-transparent');
                    activeBtn.classList.add('text-white', 'border-purple-500', 'bg-zinc-900/50');
                    
                    if (tabName === 'weekly') {
                        loadWeeklyData();
                    } else if (tabName === 'settings') {
                        loadRulesData();
                    } else if (tabName === 'ai') {
                        updateAIDateDisplays();
                        loadData();
                    } else {
                        loadData();
                    }
                }

                function setToday() {
                    currentDate = formatLocalDate(new Date());
                    document.getElementById('date-picker').value = currentDate;
                    triggerTabRefresh();
                }

                function dateChanged() {
                    currentDate = document.getElementById('date-picker').value;
                    triggerTabRefresh();
                }

                function navigateDate(offset) {
                    const parts = currentDate.split('-');
                    let d = new Date(parts[0], parts[1] - 1, parts[2]);
                    d.setDate(d.getDate() + offset);
                    currentDate = formatLocalDate(d);
                    document.getElementById('date-picker').value = currentDate;
                    triggerTabRefresh();
                }

                function triggerTabRefresh() {
                    if (currentTab === 'weekly') {
                        loadWeeklyData();
                    } else if (currentTab === 'settings') {
                        loadRulesData();
                    } else if (currentTab === 'ai') {
                        updateAIDateDisplays();
                        loadData();
                    } else {
                        loadData();
                    }
                }

                function formatTime(secs) {
                    if (secs < 60) return Math.round(secs) + 's';
                    let mins = Math.floor(secs / 60);
                    let hrs = Math.floor(mins / 60);
                    mins = mins % 60;
                    if (hrs > 0) return hrs + 'h ' + mins + 'm';
                    return mins + 'm';
                }

                function loadData() {
                    // Pre-populate availableCategories from rules first
                    fetch('/api/rules')
                        .then(res => res.json())
                        .then(rules => {
                            rules.forEach(rule => {
                                if (rule.category && !availableCategories.includes(rule.category)) {
                                    availableCategories.push(rule.category);
                                }
                            });
                            
                            // Now fetch stats
                            return fetch('/api/stats?date=' + currentDate + '&device=' + encodeURIComponent(currentDevice));
                        })
                        .then(res => res.json())
                        .then(data => {
                            // Update metrics
                            document.getElementById('stat-active').innerText = formatTime(data.totalActive);
                            document.getElementById('stat-idle').innerText = formatTime(data.totalIdle);
                            document.getElementById('stat-events').innerText = data.timeline.length;

                            // Add any timeline categories
                            data.timeline.forEach(ev => {
                                if (ev.category && !ev.isIdle && !availableCategories.includes(ev.category)) {
                                    availableCategories.push(ev.category);
                                }
                            });

                            // Calculate focus score
                            const fTime = data.focusedTime || 0.0;
                            const mTime = data.multitaskingTime || 0.0;
                            const totalTime = fTime + mTime;
                            const score = totalTime > 0 ? Math.round((fTime / totalTime) * 100) : 0;
                            
                            document.getElementById('stat-focus-score').innerText = score + '%';
                            document.getElementById('stat-focus-sub').innerText = `Focus: ${formatTime(fTime)} | Multitask: ${formatTime(mTime)}`;

                            // Update Charts
                            renderCategoryChart(data.categoryStats);
                            renderAppsChart(data.appStats);

                            // Update Timeline
                            currentEvents = data.timeline;
                            renderTimeline(currentEvents);
                        })
                        .catch(err => console.error("Error fetching stats:", err));
                }

                function renderCategoryChart(catStats) {
                    const ctx = document.getElementById('categoryChart').getContext('2d');
                    const labels = Object.keys(catStats);
                    const values = Object.values(catStats).map(v => Math.round((v / 60.0) * 10) / 10); // convert to minutes

                    if (labels.length === 0) {
                        labels.push("No Active Data");
                        values.push(1);
                    }

                    if (categoryChartInstance) {
                        categoryChartInstance.destroy();
                    }

                    categoryChartInstance = new Chart(ctx, {
                        type: 'doughnut',
                        data: {
                            labels: labels,
                            datasets: [{
                                data: values,
                                backgroundColor: labels.map(l => getCategoryColor(l)),
                                borderWidth: 1,
                                borderColor: '#18181b'
                            }]
                        },
                        options: {
                            responsive: true,
                            maintainAspectRatio: false,
                            plugins: {
                                legend: {
                                    position: 'bottom',
                                    labels: { color: '#a1a1aa', font: { family: 'Inter' } }
                                }
                            }
                        }
                    });
                }

                function renderAppsChart(appStats) {
                    const ctx = document.getElementById('appsChart').getContext('2d');
                    const topApps = appStats.slice(0, 6);
                    const labels = topApps.map(a => a.appName);
                    const values = topApps.map(a => a.duration / 60.0); // minutes

                    if (appsChartInstance) {
                        appsChartInstance.destroy();
                    }

                    appsChartInstance = new Chart(ctx, {
                        type: 'bar',
                        data: {
                            labels: labels,
                            datasets: [{
                                label: 'Duration (Minutes)',
                                data: values,
                                backgroundColor: 'rgba(139, 92, 246, 0.7)',
                                borderColor: '#8b5cf6',
                                borderWidth: 1,
                                borderRadius: 6
                            }]
                        },
                        options: {
                            indexAxis: 'y',
                            responsive: true,
                            maintainAspectRatio: false,
                            scales: {
                                x: { grid: { color: '#27272a' }, ticks: { color: '#71717a' } },
                                y: { grid: { display: false }, ticks: { color: '#e4e4e7' } }
                            },
                            plugins: {
                                legend: { display: false }
                            }
                        }
                    });
                }

                function renderTimeline(events) {
                    const body = document.getElementById('timeline-body');
                    body.innerHTML = '';

                    if (events.length === 0) {
                        body.innerHTML = `
                            <tr>
                                <td colspan="6" class="py-8 text-center text-zinc-500">No events logged on this date.</td>
                            </tr>
                        `;
                        return;
                    }

                    let sorted = [...events];
                    sorted.sort((a, b) => {
                        let valA, valB;
                        if (currentSortKey === 'time') {
                            valA = a.startTime;
                            valB = b.startTime;
                        } else if (currentSortKey === 'duration') {
                            valA = a.duration;
                            valB = b.duration;
                        } else if (currentSortKey === 'category') {
                            valA = a.category;
                            valB = b.category;
                        } else if (currentSortKey === 'appName') {
                            valA = a.appName.toLowerCase();
                            valB = b.appName.toLowerCase();
                        }

                        if (valA < valB) return currentSortOrder === 'asc' ? -1 : 1;
                        if (valA > valB) return currentSortOrder === 'asc' ? 1 : -1;
                        return 0;
                    });

                    sorted.forEach(ev => {
                        const row = document.createElement('tr');
                        row.className = ev.isIdle ? "hover:bg-zinc-900/20 text-zinc-500" : "hover:bg-zinc-900/40 cursor-pointer";
                        if (!ev.isIdle) {
                            row.title = "Click to prefill Create Rule form above";
                            row.onclick = (e) => {
                                if (e.target.tagName === 'SELECT' || e.target.tagName === 'OPTION') return;
                                quickRule(ev.appName, ev.windowTitle, ev.category);
                            };
                        }
                        
                        let selectHtml = '';
                        if (ev.isIdle) {
                            selectHtml = `<span class="text-xs px-2 py-1 rounded bg-zinc-800 text-zinc-500 border border-zinc-700">Idle</span>`;
                        } else {
                            selectHtml = `<select onchange="handleCategorySelectChange(${ev.id}, this)" class="bg-zinc-950 border border-zinc-800 rounded px-2 py-1 text-xs text-zinc-300 focus:outline-none focus:ring-1 focus:ring-purple-600 w-32">`;
                            availableCategories.forEach(c => {
                                selectHtml += `<option value="${c}" ${ev.category === c ? 'selected' : ''}>${c}</option>`;
                            });
                            selectHtml += `<option value="__custom__">+ Add Custom...</option>`;
                            selectHtml += `</select>`;
                        }

                        row.innerHTML = `
                            <td class="py-3.5 px-6 font-mono text-xs">${ev.startTime}</td>
                            <td class="py-3.5 px-6 font-semibold ${ev.isIdle ? 'text-zinc-500' : 'text-zinc-100'}">${ev.appName}</td>
                            <td class="py-3.5 px-6 max-w-xs truncate" title="${ev.windowTitle}">${ev.windowTitle}</td>
                            <td class="py-3.5 px-6 font-mono text-xs">${formatTime(ev.duration)}</td>
                            <td class="py-3.5 px-6">${selectHtml}</td>
                        `;
                        body.appendChild(row);
                    });
                }

                function handleCategorySelectChange(eventId, selectElement) {
                    const value = selectElement.value;
                    const ev = currentEvents.find(e => e.id === eventId);
                    if (ev) {
                        quickRule(ev.appName, ev.windowTitle, value);
                    }
                    if (value === "__custom__") {
                        const customCat = prompt("Enter custom category / topic name:");
                        if (customCat && customCat.trim() !== "") {
                            const trimmed = customCat.trim();
                            if (!availableCategories.includes(trimmed)) {
                                availableCategories.push(trimmed);
                            }
                            if (ev) {
                                quickRule(ev.appName, ev.windowTitle, trimmed);
                            }
                            updateEventCategory(eventId, trimmed);
                        } else {
                            loadData();
                        }
                    } else {
                        updateEventCategory(eventId, value);
                    }
                }

                function updateEventCategory(eventId, category) {
                    fetch('/api/categorize', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ eventId: eventId, category: category })
                    })
                    .then(res => res.json())
                    .then(data => {
                        if (data.success) {
                            loadData();
                        }
                    })
                    .catch(err => console.error("Error updating category:", err));
                }

                function quickRule(appName, title, category) {
                    document.getElementById('rule-app').value = appName;
                    
                    let suggestedPattern = '';
                    if (title.includes('YouTube')) suggestedPattern = 'YouTube';
                    else if (title.includes('Netflix')) suggestedPattern = 'Netflix';
                    else suggestedPattern = title.split(' - ')[0] || title;
                    
                    document.getElementById('rule-title').value = suggestedPattern;
                    document.getElementById('rule-category').value = category;
                    
                    document.getElementById('rule-form').scrollIntoView({ behavior: 'smooth' });
                }

                function submitRule(event) {
                    event.preventDefault();
                    
                    const appName = document.getElementById('rule-app').value;
                    const titlePattern = document.getElementById('rule-title').value;
                    const category = document.getElementById('rule-category').value;

                    if (!appName && !titlePattern) {
                        alert("Please specify at least an application name or a window title pattern!");
                        return;
                    }

                    fetch('/api/categorize', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ appName: appName, titlePattern: titlePattern, category: category })
                    })
                    .then(res => res.json())
                    .then(data => {
                        if (data.success) {
                            document.getElementById('rule-app').value = '';
                            document.getElementById('rule-title').value = '';
                            document.getElementById('rule-category').value = '';
                            loadData();
                        }
                    })
                    .catch(err => console.error("Error submitting rule:", err));
                }


                // ==========================================
                // TAB 2: WEEKLY REPORT LOGIC
                // ==========================================
                function loadWeeklyData() {
                    fetch('/api/weekly-stats?date=' + currentDate + '&device=' + encodeURIComponent(currentDevice))
                        .then(res => res.json())
                        .then(data => {
                            const thisActive = data.thisWeek.active || 0.0;
                            const thisIdle = data.thisWeek.idle || 0.0;
                            const thisFocus = data.thisWeek.focused || 0.0;
                            const thisMulti = data.thisWeek.multitasking || 0.0;
                            
                            const priorActive = data.priorWeek.active || 0.0;
                            const priorIdle = data.priorWeek.idle || 0.0;
                            const priorFocus = data.priorWeek.focused || 0.0;
                            const priorMulti = data.priorWeek.multitasking || 0.0;

                            document.getElementById('weekly-active').innerText = formatTime(thisActive);
                            document.getElementById('weekly-idle').innerText = formatTime(thisIdle);
                            
                            const thisTotal = thisFocus + thisMulti;
                            const thisFocusScore = thisTotal > 0 ? Math.round((thisFocus / thisTotal) * 100) : 0;
                            document.getElementById('weekly-focus').innerText = thisFocusScore + '%';

                            const activeDiff = thisActive - priorActive;
                            const activeDiffStr = formatTime(Math.abs(activeDiff));
                            document.getElementById('weekly-active-compare').innerText = activeDiff >= 0 
                                ? `+${activeDiffStr} vs. Last Week` 
                                : `-${activeDiffStr} vs. Last Week`;
                                
                            const idleDiff = thisIdle - priorIdle;
                            const idleDiffStr = formatTime(Math.abs(idleDiff));
                            document.getElementById('weekly-idle-compare').innerText = idleDiff >= 0 
                                ? `+${idleDiffStr} vs. Last Week` 
                                : `-${idleDiffStr} vs. Last Week`;

                            const priorTotal = priorFocus + priorMulti;
                            const priorFocusScore = priorTotal > 0 ? Math.round((priorFocus / priorTotal) * 100) : 0;
                            const focusDiff = thisFocusScore - priorFocusScore;
                            document.getElementById('weekly-focus-compare').innerText = focusDiff >= 0 
                                ? `+${focusDiff}% vs. Last Week` 
                                : `${focusDiff}% vs. Last Week`;

                            renderWeeklyTrendChart(data.dailyStats);
                            renderWeeklyFocusChart(data.dailyStats);
                            renderWeeklyCategoryChart(data.categoryStats);
                        })
                        .catch(err => console.error("Error loading weekly stats:", err));
                }

                function renderWeeklyTrendChart(dailyStats) {
                    const ctx = document.getElementById('weeklyTrendChart').getContext('2d');
                    const labels = dailyStats.map(s => s.date.substring(5)); 
                    const activeValues = dailyStats.map(s => Math.round((s.active / 60.0) * 10) / 10); // convert to minutes
                    const idleValues = dailyStats.map(s => Math.round((s.idle / 60.0) * 10) / 10); // convert to minutes

                    if (weeklyTrendChartInstance) {
                        weeklyTrendChartInstance.destroy();
                    }

                    weeklyTrendChartInstance = new Chart(ctx, {
                        type: 'bar',
                        data: {
                            labels: labels,
                            datasets: [
                                {
                                    label: 'Active (Minutes)',
                                    data: activeValues,
                                    backgroundColor: 'rgba(59, 130, 246, 0.75)',
                                    borderColor: '#3b82f6',
                                    borderWidth: 1,
                                    borderRadius: 4
                                },
                                {
                                    label: 'Away (Minutes)',
                                    data: idleValues,
                                    backgroundColor: 'rgba(63, 63, 70, 0.75)',
                                    borderColor: '#3f3f46',
                                    borderWidth: 1,
                                    borderRadius: 4
                                }
                            ]
                        },
                        options: {
                            responsive: true,
                            maintainAspectRatio: false,
                            scales: {
                                x: { grid: { color: '#27272a' }, ticks: { color: '#71717a' } },
                                y: { grid: { color: '#27272a' }, ticks: { color: '#71717a' } }
                            },
                            plugins: {
                                legend: { labels: { color: '#a1a1aa' } }
                            }
                        }
                    });
                }

                function renderWeeklyFocusChart(dailyStats) {
                    const ctx = document.getElementById('weeklyFocusChart').getContext('2d');
                    const labels = dailyStats.map(s => s.date.substring(5));
                    const focusScores = dailyStats.map(s => {
                        const total = s.focused + s.multitasking;
                        return total > 0 ? Math.round((s.focused / total) * 100) : 0;
                    });

                    if (weeklyFocusChartInstance) {
                        weeklyFocusChartInstance.destroy();
                    }

                    weeklyFocusChartInstance = new Chart(ctx, {
                        type: 'line',
                        data: {
                            labels: labels,
                            datasets: [{
                                label: 'Focus Score %',
                                data: focusScores,
                                borderColor: '#10b981',
                                backgroundColor: 'rgba(16, 185, 129, 0.1)',
                                fill: true,
                                tension: 0.35,
                                borderWidth: 2,
                                pointBackgroundColor: '#10b981'
                            }]
                        },
                        options: {
                            responsive: true,
                            maintainAspectRatio: false,
                            scales: {
                                x: { grid: { color: '#27272a' }, ticks: { color: '#71717a' } },
                                y: { grid: { color: '#27272a' }, ticks: { color: '#71717a' }, min: 0, max: 100 }
                            },
                            plugins: {
                                legend: { display: false }
                            }
                        }
                    });
                }

                function renderWeeklyCategoryChart(catStats) {
                    const ctx = document.getElementById('weeklyCategoryChart').getContext('2d');
                    const labels = Object.keys(catStats);
                    const values = Object.values(catStats).map(v => Math.round((v / 60.0) * 10) / 10); // convert to minutes

                    if (labels.length === 0) {
                        labels.push("No Data");
                        values.push(0.1);
                    }

                    if (weeklyCategoryChartInstance) {
                        weeklyCategoryChartInstance.destroy();
                    }

                    weeklyCategoryChartInstance = new Chart(ctx, {
                        type: 'doughnut',
                        data: {
                            labels: labels,
                            datasets: [{
                                data: values,
                                backgroundColor: labels.map(l => getCategoryColor(l)),
                                borderWidth: 1,
                                borderColor: '#18181b'
                            }]
                        },
                        options: {
                            responsive: true,
                            maintainAspectRatio: false,
                            plugins: {
                                legend: {
                                    position: 'bottom',
                                    labels: { color: '#a1a1aa' }
                                }
                            }
                        }
                    });
                }

                // ==========================================
                // TAB 3: RULES & SETTINGS LOGIC
                // ==========================================
                function loadRulesData() {
                    loadAutoStartSetting();
                    fetch('/api/rules')
                        .then(res => res.json())
                        .then(data => {
                            data.forEach(rule => {
                                if (rule.category && !availableCategories.includes(rule.category)) {
                                    availableCategories.push(rule.category);
                                }
                            });
                            renderRulesList(data);
                        })
                        .catch(err => console.error("Error loading rules:", err));
                }

                function renderRulesList(rules) {
                    const body = document.getElementById('rules-list-body');
                    body.innerHTML = '';

                    if (rules.length === 0) {
                        body.innerHTML = `
                            <tr>
                                <td colspan="4" class="py-8 text-center text-zinc-500">No categorization rules found. Create one above!</td>
                            </tr>
                        `;
                        return;
                    }

                    rules.forEach(rule => {
                        const row = document.createElement('tr');
                        row.className = "hover:bg-zinc-900/40";
                        row.innerHTML = `
                            <td class="py-3.5 px-6 font-semibold text-zinc-100">${rule.appName || '<span class="text-zinc-600">Any</span>'}</td>
                            <td class="py-3.5 px-6 font-mono text-xs text-zinc-300">${rule.titlePattern || '<span class="text-zinc-600">Any</span>'}</td>
                            <td class="py-3.5 px-6"><span class="px-2.5 py-0.5 rounded-full text-xs font-semibold bg-purple-950/40 text-purple-300 border border-purple-800/40">${rule.category}</span></td>
                            <td class="py-3.5 px-6 text-right">
                                <button onclick="deleteRule(${rule.id})" class="text-xs text-red-400 hover:text-red-300 hover:bg-red-950/30 px-3 py-1.5 rounded transition">
                                    Delete
                                </button>
                            </td>
                        `;
                        body.appendChild(row);
                    });
                }

                function submitSettingsRule(event) {
                    event.preventDefault();
                    const appName = document.getElementById('set-rule-app').value;
                    const titlePattern = document.getElementById('set-rule-title').value;
                    const category = document.getElementById('set-rule-category').value;

                    if (!appName && !titlePattern) {
                        alert("Please specify at least an application name or a window title pattern!");
                        return;
                    }
                    if (!category) {
                        alert("Please specify a category / topic!");
                        return;
                    }

                    fetch('/api/categorize', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ appName: appName, titlePattern: titlePattern, category: category })
                    })
                    .then(res => res.json())
                    .then(data => {
                        if (data.success) {
                            document.getElementById('set-rule-app').value = '';
                            document.getElementById('set-rule-title').value = '';
                            document.getElementById('set-rule-category').value = '';
                            loadRulesData();
                        }
                    })
                    .catch(err => console.error("Error creating rule:", err));
                }

                function deleteRule(ruleId) {
                    if (!confirm("Are you sure you want to delete this rule? Past events categorized by this rule will be updated to reflect the change.")) return;
                    
                    fetch('/api/rules/delete', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ id: ruleId })
                    })
                    .then(res => res.json())
                    .then(data => {
                        if (data.success) {
                            loadRulesData();
                        }
                    })
                    .catch(err => console.error("Error deleting rule:", err));
                }

                function exportRawData() {
                    fetch('/api/export?date=' + currentDate + '&device=' + encodeURIComponent(currentDevice))
                        .then(res => res.json())
                        .then(data => {
                            const dataStr = "data:text/json;charset=utf-8," + encodeURIComponent(JSON.stringify(data, null, 2));
                            const downloadAnchor = document.createElement('a');
                            downloadAnchor.setAttribute("href", dataStr);
                            downloadAnchor.setAttribute("download", `second_brain_export_${currentDate}.json`);
                            document.body.appendChild(downloadAnchor);
                            downloadAnchor.click();
                            downloadAnchor.remove();
                        })
                        .catch(err => {
                            console.error("Export failed:", err);
                            alert("Export failed: " + err);
                        });
                }

                function loadAutoStartSetting() {
                    fetch('/api/autostart')
                        .then(res => res.json())
                        .then(data => {
                            document.getElementById('autostart-toggle').checked = data.enabled;
                        })
                        .catch(err => console.error("Error loading autostart setting:", err));
                }

                function toggleAutoStart(checkbox) {
                    const enabled = checkbox.checked;
                    fetch('/api/autostart', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ enabled: enabled })
                    })
                    .then(res => res.json())
                    .then(data => {
                        if (!data.success) {
                            alert("Failed to update auto-start setting.");
                            checkbox.checked = !enabled;
                        }
                    })
                    .catch(err => {
                        console.error("Error updating autostart setting:", err);
                        alert("Error updating auto-start setting: " + err);
                        checkbox.checked = !enabled;
                    });
                }

                // ==========================================
                // TAB 4: LOCAL AI CHAT LOGIC
                // ==========================================
                document.addEventListener("DOMContentLoaded", () => {
                    loadAISettings();
                    updateAIDateDisplays();
                });

                function updateAIDateDisplays() {
                    const displays = document.querySelectorAll('.current-date-display');
                    displays.forEach(el => {
                        el.innerText = currentDate;
                    });
                }

                 function loadAISettings() {
                    const endpoint = localStorage.getItem("SB_AI_ENDPOINT") || "http://localhost:11434/v1/chat/completions";
                    const model = localStorage.getItem("SB_AI_MODEL") || "llama3";
                    document.getElementById("ai-endpoint").value = endpoint;
                    document.getElementById("ai-model").value = model;
                    
                    fetch('/api/system-prompt')
                        .then(res => res.json())
                        .then(data => {
                            if (data.prompt) {
                                document.getElementById("ai-system-prompt").value = data.prompt;
                                localStorage.setItem("SB_AI_SYSTEM_PROMPT", data.prompt);
                            }
                        })
                        .catch(err => {
                            console.error("Could not load system prompt from file, falling back to local storage:", err);
                            const systemPrompt = localStorage.getItem("SB_AI_SYSTEM_PROMPT") || "You are Mitthu Assistant, a privacy-first local AI productivity expert. You analyze screen time, categorize activities, identify distractions, and suggest learning strategies like Spaced Repetition, Active Recall, and the Feynman Technique. Always format your responses in a clean, human-friendly, point-wise (bulleted) structure. Avoid long paragraphs and make it easy to scan at a glance.";
                            document.getElementById("ai-system-prompt").value = systemPrompt;
                        });
                }

                function saveAISettings() {
                    const endpoint = document.getElementById("ai-endpoint").value.trim();
                    const model = document.getElementById("ai-model").value.trim();
                    const systemPrompt = document.getElementById("ai-system-prompt").value.trim();
                    if (!endpoint || !model) {
                        alert("Endpoint and Model Name cannot be empty.");
                        return;
                    }
                    localStorage.setItem("SB_AI_ENDPOINT", endpoint);
                    localStorage.setItem("SB_AI_MODEL", model);
                    localStorage.setItem("SB_AI_SYSTEM_PROMPT", systemPrompt);
                    
                    fetch('/api/system-prompt', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ prompt: systemPrompt })
                    })
                    .then(res => res.json())
                    .then(data => {
                        if (data.success) {
                            alert("Saved in cache and instructions.md successfully!");
                        } else {
                            alert("Saved in cache but failed to update instructions.md: " + data.error);
                        }
                    })
                    .catch(err => {
                        console.error("Error saving system prompt to disk:", err);
                        alert("Saved in cache (instructions.md write failed).");
                    });
                }

                function clearChatLog() {
                    const log = document.getElementById("ai-chat-log");
                    log.innerHTML = '';
                    
                    const welcome = document.createElement('div');
                    welcome.id = "chat-welcome-card";
                    welcome.className = "max-w-md mx-auto text-center space-y-4 py-8 select-none";
                    welcome.innerHTML = `
                        <div class="w-12 h-12 rounded-2xl bg-gradient-to-tr from-purple-600 to-indigo-600 flex items-center justify-center mx-auto shadow-lg shadow-purple-500/20">
                            <span class="text-2xl">🦜</span>
                        </div>
                        <h4 class="font-heading font-semibold text-white text-base">Local AI Brain Sync</h4>
                        <p class="text-xs text-zinc-400 leading-relaxed">
                            Ask questions about your daily screen behavior, get focus insights, or let the AI analyze your timeline log. Ensure your local LLM (Ollama or LM Studio) is running on localhost!
                        </p>
                        <div class="text-[10px] text-zinc-500 border border-zinc-800 rounded-lg p-2.5 bg-zinc-950/40 max-w-sm mx-auto text-left leading-normal">
                            <strong>Trouble connecting?</strong> If requests fail, verify CORS is allowed. For Ollama on macOS, run: <code class="text-purple-300 font-mono text-[9px]">OLLAMA_ORIGINS="*" ollama serve</code>
                        </div>
                    `;
                    log.appendChild(welcome);
                }

                function formatMarkdown(text) {
                    let html = text
                        .replace(/&/g, "&amp;")
                        .replace(/</g, "&lt;")
                        .replace(/>/g, "&gt;");
                    
                    html = html.replace(/```([\\s\\S]*?)```/g, '<pre class="bg-black/60 border border-zinc-800 p-3 rounded-lg font-mono text-xs overflow-x-auto my-2 text-purple-300">$1</pre>');
                    html = html.replace(/`([^`]+)`/g, '<code class="bg-black/40 border border-zinc-800 px-1 py-0.5 rounded font-mono text-xs text-purple-400">$1</code>');
                    html = html.replace(/\\*\\*(.*?)\\*\\*/g, '<strong>$1</strong>');
                    html = html.replace(/\\*(.*?)\\*/g, '<em>$1</em>');
                    
                    // Render headings
                    html = html.replace(/^### (.*?)$/gm, '<h3 class="text-sm font-bold text-purple-400 mt-3 mb-1">$1</h3>');
                    html = html.replace(/^## (.*?)$/gm, '<h2 class="text-base font-bold text-purple-355 mt-4 mb-2">$1</h2>');
                    html = html.replace(/^# (.*?)$/gm, '<h1 class="text-lg font-bold text-white mt-4 mb-2">$1</h1>');
                    
                    // Render horizontal rules
                    html = html.replace(/^---$/gm, '<hr class="border-zinc-800 my-3">');
                    
                    // Render bullet points
                    html = html.replace(/^\\* (.*?)$/gm, '• $1');
                    html = html.replace(/^- (.*?)$/gm, '• $1');
                    
                    return html;
                }

                function appendChatMessage(sender, text, isThinking = false) {
                    const log = document.getElementById("ai-chat-log");
                    
                    const welcome = document.getElementById("chat-welcome-card");
                    if (welcome) welcome.remove();
                    
                    const existingThinking = document.getElementById("ai-thinking-bubble");
                    if (existingThinking) existingThinking.remove();
                    
                    const msg = document.createElement("div");
                    msg.className = "flex " + (sender === "user" ? "justify-end" : "justify-start") + " animate-fadeIn";
                    
                    if (isThinking) {
                        msg.id = "ai-thinking-bubble";
                    }
                    
                    const inner = document.createElement("div");
                    inner.className = "max-w-[80%] rounded-2xl px-4 py-2.5 text-sm shadow-md " + 
                        (sender === "user" 
                            ? "bg-purple-600 text-white rounded-br-none" 
                            : "bg-zinc-900 border border-zinc-800 text-zinc-200 rounded-bl-none");
                            
                    if (isThinking) {
                        inner.innerHTML = `
                            <div class="flex items-center space-x-1 py-1 px-2">
                                <div class="w-1.5 h-1.5 bg-purple-400 rounded-full animate-bounce" style="animation-delay: 0ms"></div>
                                <div class="w-1.5 h-1.5 bg-purple-400 rounded-full animate-bounce" style="animation-delay: 150ms"></div>
                                <div class="w-1.5 h-1.5 bg-purple-400 rounded-full animate-bounce" style="animation-delay: 300ms"></div>
                            </div>
                        `;
                    } else {
                        inner.innerHTML = `<div class="leading-relaxed whitespace-pre-wrap text-xs md:text-sm">${formatMarkdown(text)}</div>`; 
                    }
                    
                    msg.appendChild(inner);
                    log.appendChild(msg);
                    log.scrollTop = log.scrollHeight;
                    
                    return msg;
                }

                async function submitChatMessage(event) {
                    if (event) event.preventDefault();
                    
                    const promptInput = document.getElementById("ai-user-prompt");
                    const userText = promptInput.value.trim();
                    if (!userText) return;
                    
                    promptInput.value = '';
                    
                    appendChatMessage("user", userText);
                    
                    let contextPayload = "";
                    const includeStats = document.getElementById("ai-ctx-stats").checked;
                    const includeTimeline = document.getElementById("ai-ctx-timeline").checked;
                    
                    if (includeStats || includeTimeline) {
                        try {
                            const statsRes = await fetch('/api/stats?date=' + currentDate + '&device=' + encodeURIComponent(currentDevice));
                            const statsData = await statsRes.json();
                            
                            const totalActive = formatTime(statsData.totalActive);
                            const totalIdle = formatTime(statsData.totalIdle);
                            
                            const fTime = statsData.focusedTime || 0.0;
                            const mTime = statsData.multitaskingTime || 0.0;
                            const totalTime = fTime + mTime;
                            const focusScore = totalTime > 0 ? Math.round((fTime / totalTime) * 100) : 0;
                            
                            let statsContext = `Daily Stats for date ${statsData.date}:\nActive Time: ${totalActive}, Idle/Away Time: ${totalIdle}, Focus Score: ${focusScore}%.\n`;
                            if (includeStats) {
                                const appsText = (statsData.appStats || []).slice(0, 8).map(a => `- ${a.appName}: ${formatTime(a.duration)}`).join('\n');
                                statsContext += `Top Apps:\n${appsText}\n`;
                            }
                            
                            // Find all specific study/focus window titles visited today
                            const focusEvents = (statsData.timeline || []).filter(e => e.category === 'Study' || e.category === 'Coding' || (e.category !== 'Entertainment' && e.category !== 'Social' && e.category !== 'Idle' && e.category !== 'Uncategorized'));
                            const uniqueFocusTitles = Array.from(new Set(focusEvents.map(e => {
                                let title = e.windowTitle.trim();
                                if (!title) return '';
                                return `${e.appName} - "${title}"`;
                            }).filter(t => t !== '')));
                            
                            if (uniqueFocusTitles.length > 0) {
                                statsContext += `\nSpecific Study/Focus Window Titles Visited Today:\n` + uniqueFocusTitles.map(t => `- ${t}`).join('\n') + `\n`;
                            }
                            
                            if (includeTimeline) {
                                let filteredTimeline = (statsData.timeline || []).filter(e => e.duration >= 30);
                                let compressed = [];
                                let current = null;
                                for (let item of filteredTimeline) {
                                    if (!current) {
                                        current = { app: item.appName, cat: item.category, titles: new Set([item.windowTitle]), start: item.startTime, dur: item.duration };
                                    } else if (current.app === item.appName && current.cat === item.category && compressed.length < 30) {
                                        current.dur += item.duration;
                                        current.titles.add(item.windowTitle);
                                    } else {
                                        compressed.push(current);
                                        current = { app: item.appName, cat: item.category, titles: new Set([item.windowTitle]), start: item.startTime, dur: item.duration };
                                    }
                                }
                                if (current) compressed.push(current);
                                
                                const timelineText = compressed.slice(0, 20).map(c => `[${c.start}] ${c.app} (${c.cat}): ${formatTime(c.dur)} - "${Array.from(c.titles).slice(0, 2).join(' | ').substring(0, 80)}"`).join('\n');
                                statsContext += `\nTimeline Events (Filtered & Aggregated):\n${timelineText}\n`;
                            }
                            
                            contextPayload = statsContext;
                        } catch (e) {
                            console.error("Error fetching stats for context:", e);
                        }
                    }
                    
                    appendChatMessage("assistant", "", true);
                    
                    let endpoint = document.getElementById("ai-endpoint").value.trim();
                    if (endpoint.endsWith('/v1')) {
                        endpoint = endpoint + '/chat/completions';
                    } else if (!endpoint.endsWith('/v1/chat/completions') && !endpoint.endsWith('/chat/completions')) {
                        if (endpoint.endsWith('/')) {
                            endpoint = endpoint + 'v1/chat/completions';
                        } else {
                            endpoint = endpoint + '/v1/chat/completions';
                        }
                    }
                    const model = document.getElementById("ai-model").value.trim();
                    
                    const systemPrompt = document.getElementById("ai-system-prompt").value.trim() || "You are Mitthu Assistant, a privacy-first local AI productivity expert. You analyze screen time, categorize activities, identify distractions, and suggest learning strategies like Spaced Repetition, Active Recall, and the Feynman Technique. Always format your responses in a clean, human-friendly, point-wise (bulleted) structure. Avoid long paragraphs and make it easy to scan at a glance.";
                    let messages = [];
                    messages.push({
                        role: "system",
                        content: systemPrompt
                    });
                    
                    let finalPrompt = userText;
                    if (contextPayload) {
                        finalPrompt = `Below is the user's daily activity data for analysis:\\n\\n${contextPayload}\\n\\nUser Question: ${userText}`;
                    }
                    messages.push({ role: "user", content: finalPrompt });
                    
                    try {
                        const response = await fetch(endpoint, {
                            method: "POST",
                            headers: { "Content-Type": "application/json" },
                            body: JSON.stringify({
                                model: model,
                                messages: messages,
                                stream: true
                            })
                        });
                        
                        const thinkingBubble = document.getElementById("ai-thinking-bubble");
                        if (thinkingBubble) thinkingBubble.remove();
                        
                        if (!response.ok) {
                            throw new Error(`API returned HTTP ${response.status}`);
                        }
                        
                        const msgDiv = document.createElement("div");
                        msgDiv.className = "flex justify-start animate-fadeIn";
                        const innerDiv = document.createElement("div");
                        innerDiv.className = "max-w-[80%] rounded-2xl px-4 py-2.5 text-sm shadow-md bg-zinc-900 border border-zinc-800 text-zinc-200 rounded-bl-none leading-relaxed whitespace-pre-wrap";
                        msgDiv.appendChild(innerDiv);
                        document.getElementById("ai-chat-log").appendChild(msgDiv);
                        
                        const reader = response.body.getReader();
                        const decoder = new TextDecoder("utf-8");
                        let done = false;
                        let aiText = "";
                        
                        while (!done) {
                            const { value, done: readerDone } = await reader.read();
                            done = readerDone;
                            if (value) {
                                const chunk = decoder.decode(value, { stream: !done });
                                const lines = chunk.split("\\n");
                                for (let line of lines) {
                                    const cleaned = line.trim();
                                    if (!cleaned) continue;
                                    if (cleaned === "data: [DONE]") continue;
                                    
                                    if (cleaned.startsWith("data: ")) {
                                        try {
                                            const parsed = JSON.parse(cleaned.substring(6));
                                            const content = parsed.choices?.[0]?.delta?.content || "";
                                            aiText += content;
                                            innerDiv.innerHTML = formatMarkdown(aiText);
                                            document.getElementById("ai-chat-log").scrollTop = document.getElementById("ai-chat-log").scrollHeight;
                                        } catch (e) {}
                                    } else {
                                        try {
                                            const parsed = JSON.parse(cleaned);
                                            const content = parsed.message?.content || parsed.response || "";
                                            if (content) {
                                                aiText += content;
                                                innerDiv.innerHTML = formatMarkdown(aiText);
                                                document.getElementById("ai-chat-log").scrollTop = document.getElementById("ai-chat-log").scrollHeight;
                                            }
                                        } catch (e) {}
                                    }
                                }
                            }
                        }
                        
                    } catch (err) {
                        console.error("AI Request failed:", err);
                        const thinkingBubble = document.getElementById("ai-thinking-bubble");
                        if (thinkingBubble) thinkingBubble.remove();
                        
                        appendChatMessage("assistant", "❌ **Connection Failed**\\n\\nCould not reach the local model. Please verify:\\n1. Your local API server is running at `" + endpoint + "`\\n2. The model `" + model + "` is loaded.\\n3. CORS is allowed (for Ollama: `OLLAMA_ORIGINS=\\\"*\\\" ollama serve`)\\n\\nError details: *" + err.message + "*");
                    }
                }

                function triggerQuickAction(type) {
                    const promptInput = document.getElementById("ai-user-prompt");
                    if (type === 'summary') {
                        promptInput.value = "Analyze my screen activity stats and timeline log for today. Provide a concise, structured summary of what I worked on, my focus level, and any notable patterns.";
                    } else if (type === 'distractions') {
                        promptInput.value = "Examine my timeline logs and identify any multitasking patterns, distractions, or apps that might have broken my flow. Suggest how I can group them under rules or optimize my setup.";
                    } else if (type === 'lifestyle') {
                        promptInput.value = "Tell me about the 3 foundation pillars (Lifestyle, Mnemonic tools, and Strategy) and how sleep, active recall, and the Feynman technique help build a strong memory palace.";
                    }
                    submitChatMessage();
                }
            </script>
        </body>
        </html>
        """
    }
}
