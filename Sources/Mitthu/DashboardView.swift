import SwiftUI
import Combine

struct DashboardView: View {
    let database: Database
    @ObservedObject var tracker: Tracker
    
    @State private var totalActive: TimeInterval = 0
    @State private var totalIdle: TimeInterval = 0
    @State private var appStats: [AppStat] = []
    @State private var recentEvents: [ActivityEvent] = []
    @State private var hasAccessibilityPermission: Bool = false
    
    let timer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // Dark gradient background
            LinearGradient(
                gradient: Gradient(colors: [Color(red: 0.08, green: 0.08, blue: 0.16), Color(red: 0.04, green: 0.04, blue: 0.08)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 16) {
                // Header
                HStack {
                    LinearGradient(
                        gradient: Gradient(colors: [.purple, .blue]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: 24, height: 24)
                    .mask(
                        Image(systemName: "bird")
                            .font(.system(size: 24))
                    )
                    .shadow(color: .purple.opacity(0.5), radius: 5)
                    
                    Text("Mitthu")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: {
                        if let url = URL(string: "http://localhost:5680") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.blue.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                    .help("Open Web Dashboard")
                    
                    Button(action: {
                        NSApplication.shared.terminate(nil)
                    }) {
                        Image(systemName: "power")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Quit Application")
                }
                .padding(.horizontal)
                .padding(.top, 12)
                
                // Accessibility warning if missing
                if !hasAccessibilityPermission {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "exclamationmark.shield.fill")
                                .foregroundColor(.orange)
                            Text("Accessibility Access Needed")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        Text("Please grant access in System Settings to track window titles.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Button(action: {
                            openAccessibilitySettings()
                        }) {
                            Text("Open System Settings")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.orange.opacity(0.8))
                                .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal)
                }
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Current status card
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CURRENTLY TRACKING")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.4))
                            
                            HStack {
                                Circle()
                                    .fill(tracker.isIdle ? Color.gray : Color.green)
                                    .frame(width: 8, height: 8)
                                    .shadow(color: tracker.isIdle ? .clear : .green.opacity(0.6), radius: 3)
                                
                                Text(tracker.isIdle ? "User is Idle (AFK)" : tracker.currentAppName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                Text(formatDuration(tracker.sessionDuration))
                                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            
                            if !tracker.currentWindowTitle.isEmpty {
                                Text(tracker.currentWindowTitle)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.5))
                                    .lineLimit(1)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(12)
                        
                        // Stats Grid (Today Total)
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ACTIVE TODAY")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white.opacity(0.4))
                                Text(formatDuration(totalActive + (tracker.isIdle ? 0 : tracker.sessionDuration)))
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(.blue)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(12)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("IDLE TODAY")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white.opacity(0.4))
                                Text(formatDuration(totalIdle + (tracker.isIdle ? tracker.sessionDuration : 0)))
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(12)
                        }
                        
                        // App breakdown charts
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TOP APPLICATIONS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.4))
                                .padding(.horizontal, 4)
                            
                            if appStats.isEmpty {
                                Text("No application activity logged today.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.3))
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(Array(appStats.enumerated()), id: \.element.appName) { index, stat in
                                        VStack(spacing: 4) {
                                            HStack {
                                                Text(stat.appName)
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundColor(.white)
                                                Spacer()
                                                Text(formatDuration(stat.duration))
                                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                                    .foregroundColor(.white.opacity(0.6))
                                            }
                                            
                                            // Progress bar
                                            GeometryReader { geo in
                                                ZStack(alignment: .leading) {
                                                    RoundedRectangle(cornerRadius: 3)
                                                        .fill(Color.white.opacity(0.05))
                                                        .frame(height: 6)
                                                    
                                                    RoundedRectangle(cornerRadius: 3)
                                                        .fill(gradientForIndex(index))
                                                        .frame(width: geo.size.width * CGFloat(stat.percentage), height: 6)
                                                }
                                            }
                                            .frame(height: 6)
                                        }
                                    }
                                }
                                .padding()
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(12)
                            }
                        }
                        
                        // Recent timeline list
                        VStack(alignment: .leading, spacing: 12) {
                            Text("RECENT ACTIVITY")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.4))
                                .padding(.horizontal, 4)
                            
                            VStack(spacing: 0) {
                                ForEach(recentEvents) { event in
                                    HStack(alignment: .center, spacing: 10) {
                                        Circle()
                                            .fill(event.isIdle ? Color.gray : Color.purple)
                                            .frame(width: 6, height: 6)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(event.isIdle ? "Idle" : event.appName)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(.white)
                                            if !event.windowTitle.isEmpty {
                                                Text(event.windowTitle)
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.white.opacity(0.4))
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                        Text(formatShortTime(event.startTime))
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.4))
                                    }
                                    .padding(.vertical, 8)
                                    
                                    if event.id != recentEvents.last?.id {
                                        Divider()
                                            .background(Color.white.opacity(0.05))
                                    }
                                }
                            }
                            .padding()
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .frame(width: 360, height: 480)
        .onAppear {
            refreshData()
        }
        .onReceive(timer) { _ in
            refreshData()
        }
    }
    
    private func refreshData() {
        // Pull stats
        let stats = database.getTodayStats()
        totalActive = stats.totalActive
        totalIdle = stats.totalIdle
        
        // Pull apps
        appStats = database.getTodayAppStats()
        
        // Pull timeline
        recentEvents = database.getRecentEvents(limit: 5)
        
        // Check permission
        hasAccessibilityPermission = checkAccessibilityPermission()
    }
    
    private func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return "\(Int(duration))s"
        }
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private func formatShortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func gradientForIndex(_ index: Int) -> LinearGradient {
        let gradients = [
            Gradient(colors: [.purple, .blue]),
            Gradient(colors: [.blue, .customTeal]),
            Gradient(colors: [.pink, .purple]),
            Gradient(colors: [.orange, .yellow]),
            Gradient(colors: [.green, .emerald])
        ]
        let selected = gradients[index % gradients.count]
        return LinearGradient(gradient: selected, startPoint: .leading, endPoint: .trailing)
    }
}

// Support newer Swift color types if they fall back
extension Color {
    static let emerald = Color(red: 0.05, green: 0.8, blue: 0.4)
    static let customTeal = Color(red: 0.18, green: 0.8, blue: 0.8)
}
