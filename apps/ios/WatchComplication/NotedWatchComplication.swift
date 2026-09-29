import SwiftUI
import WidgetKit

struct NotedWatchComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchComplicationSnapshot
}

struct NotedWatchComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> NotedWatchComplicationEntry {
        NotedWatchComplicationEntry(date: Date(), snapshot: .ready)
    }

    func getSnapshot(in context: Context, completion: @escaping (NotedWatchComplicationEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NotedWatchComplicationEntry>) -> Void) {
        let current = entry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: current.date) ?? current.date.addingTimeInterval(900)
        completion(Timeline(entries: [current], policy: .after(nextRefresh)))
    }

    private func entry() -> NotedWatchComplicationEntry {
        NotedWatchComplicationEntry(date: Date(), snapshot: WatchComplicationStateStore.load())
    }
}

struct NotedWatchComplicationView: View {
    let entry: NotedWatchComplicationEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                inlineView
            case .accessoryRectangular:
                rectangularView
            default:
                circularView
            }
        }
        .widgetURL(URL(string: "noted-watch://capture"))
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    private var title: String {
        switch entry.snapshot.state {
        case .ready: "Record"
        case .recording: "REC"
        case .transferring: "Send"
        case .attention: "Check"
        }
    }

    private var symbol: String {
        switch entry.snapshot.state {
        case .ready: "record.circle.fill"
        case .recording: "waveform"
        case .transferring: "arrow.up.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch entry.snapshot.state {
        case .ready: .red
        case .recording: .red
        case .transferring: .orange
        case .attention: .yellow
        }
    }

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
        }
        .accessibilityLabel(title)
    }

    private var rectangularView: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Noted")
                    .font(.headline)
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var inlineView: some View {
        Label(statusText, systemImage: symbol)
            .foregroundStyle(tint)
    }

    private var statusText: String {
        switch entry.snapshot.state {
        case .ready: "Record"
        case .recording: "Recording \(format(entry.snapshot.elapsed))"
        case .transferring: "Transfer pending"
        case .attention: "Action needed"
        }
    }

    private func format(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded(.down)))
        return String(format: "%02d:%02d", (total / 60) % 60, total % 60)
    }
}

struct NotedWatchComplication: Widget {
    let kind = WatchComplicationStateStore.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NotedWatchComplicationProvider()) { entry in
            NotedWatchComplicationView(entry: entry)
        }
        .configurationDisplayName("Record with Noted")
        .description("Open Noted at the Watch recording start screen.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryInline,
            .accessoryRectangular
        ])
    }
}

@main
struct NotedWatchComplicationBundle: WidgetBundle {
    var body: some Widget {
        NotedWatchComplication()
    }
}
