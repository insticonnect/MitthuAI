import Foundation

struct ActivityEvent: Identifiable {
    let id: Int
    let appName: String
    let windowTitle: String
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval
    let isIdle: Bool
    let category: String
    let device: String
}

struct AppStat: Identifiable {
    var id: String { appName }
    let appName: String
    let duration: TimeInterval
    let percentage: Double
}
