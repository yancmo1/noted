import Foundation

struct WatchComplicationSnapshot: Codable, Equatable {
    enum State: String, Codable {
        case ready
        case recording
        case transferring
        case attention
    }

    let state: State
    let elapsed: TimeInterval
    let updatedAt: Date

    static let ready = WatchComplicationSnapshot(state: .ready, elapsed: 0, updatedAt: Date())
}

enum WatchComplicationLink {
    static let scheme = "noted-watch"
    static let captureHost = "capture"
    static let captureURL = URL(string: "\(scheme)://\(captureHost)")!
}

enum WatchComplicationStateStore {
    static let appGroup = "group.com.shepswork.noted.watch"
    static let snapshotKey = "watch.complication.snapshot"
    static let widgetKind = "NotedWatchComplication"

    static func load() -> WatchComplicationSnapshot {
        guard let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(WatchComplicationSnapshot.self, from: data) else {
            return .ready
        }
        return snapshot
    }

    static func save(_ snapshot: WatchComplicationSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }
}
