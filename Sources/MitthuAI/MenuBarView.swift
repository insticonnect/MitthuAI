import SwiftUI
import AppKit
import Combine

/// View state for the popover. An ObservableObject instead of @State so the
/// app builds with plain swiftc on SDKs where @State is a compiler macro.
final class MenuBarModel: ObservableObject {
    @Published var paused = Config.shared.paused
    @Published var activeToday = ""
    @Published var importantCount = 0
}

/// The popover shown from the menu bar icon.
struct MenuBarView: View {
    @ObservedObject var tracker: Tracker
    let store: Store
    let openDashboard: () -> Void
    @ObservedObject var model: MenuBarModel

    // Refresh the live counts (active time, needs-attention) every few seconds
    // while the popover is open, so they reflect changes you make elsewhere.
    private let ticker = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    init(tracker: Tracker, store: Store, openDashboard: @escaping () -> Void) {
        self.tracker = tracker
        self.store = store
        self.openDashboard = openDashboard
        self.model = MenuBarModel()
    }

    var body: some View {
        VStack(spacing: 0) {
            brandBar
            details
        }
        .frame(width: 280)
        .onAppear(perform: refresh)
        .onReceive(ticker) { _ in refresh() }
    }

    /// The mitthuai.com nav, shrunk to fit the popover: parrot mark plus the
    /// white wordmark on the brand's ink background.
    private var brandBar: some View {
        HStack(spacing: 9) {
            Image(nsImage: BrandLogo.image(size: BrandLogo.wordmarkSize + 4))
                .accessibilityLabel("MitthuAI logo")
            Text("MitthuAI")
                // .weight keeps it bold if the bundled face is ever missing and
                // the system font stands in.
                .font(.custom(BrandLogo.wordmarkFontName, size: BrandLogo.wordmarkSize).weight(.bold))
                .foregroundColor(Color(BrandLogo.color(BrandLogo.wordmarkHex)))
            Spacer()
            Circle()
                .fill(model.paused ? Color.orange : Color.green)
                .frame(width: 9, height: 9)
            Text(model.paused ? "Paused" : "Tracking")
                .font(.caption)
                .foregroundColor(Color(BrandLogo.color(BrandLogo.wordmarkHex)).opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color(BrandLogo.color(BrandLogo.inkHex)))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tracker.isIdle ? "Idle" : tracker.currentAppName)
                    .font(.system(size: 13, weight: .semibold))
                if !tracker.currentWindowTitle.isEmpty && !tracker.isIdle {
                    Text(tracker.currentWindowTitle)
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Active today").font(.caption2).foregroundColor(.secondary)
                    Text(model.activeToday).font(.system(size: 15, weight: .bold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Needs attention").font(.caption2).foregroundColor(.secondary)
                    Text("\(model.importantCount)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(model.importantCount > 0 ? .orange : .primary)
                }
            }

            Divider()

            Button(action: openDashboard) {
                Label("Open Dashboard", systemImage: "rectangle.on.rectangle")
                    .frame(maxWidth: .infinity)
            }

            Button(action: togglePause) {
                Label(model.paused ? "Resume Tracking" : "Pause Tracking",
                      systemImage: model.paused ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
            }

            // "Open at Login" lives in the dashboard's Settings → Startup; it
            // is a set-once choice, not something to carry in the dropdown.

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Label("Quit MitthuAI", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
    }

    private func togglePause() {
        Config.shared.paused.toggle()
        Config.shared.save()
        model.paused = Config.shared.paused
    }

    private func refresh() {
        model.paused = Config.shared.paused
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let stats = store.statsForDate(fmt.string(from: Date()))
        model.activeToday = Digest.formatDuration(stats.active)
        let imp = store.importantToday()
        let dueSoon = (imp["due_soon"] as? [[String: Any]])?.count ?? 0
        let revisions = (imp["revisions_today"] as? [[String: Any]])?.count ?? 0
        model.importantCount = dueSoon + revisions
    }
}
