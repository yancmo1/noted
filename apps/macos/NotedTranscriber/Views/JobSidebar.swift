import SwiftUI

struct JobSidebar: View {
    @Bindable var store: TranscriptionStore

    var body: some View {
        List(selection: $store.selection) {
            ForEach(store.jobs) { job in
                JobRow(job: job)
                    .tag(job.id)
                    .contextMenu {
                        Button("Show Recording in Finder") { store.revealSource(job) }
                        Button("Show Transcript Files") { store.revealOutput(job) }
                        Divider()
                        Button("Remove from List", role: .destructive) { store.remove(job.id) }
                    }
            }
        }
        .navigationTitle("Recordings")
        .overlay {
            if store.jobs.isEmpty {
                ContentUnavailableView(
                    "No recordings yet",
                    systemImage: "waveform",
                    description: Text("Drop a recording into Noted Transcriber to begin.")
                )
            }
        }
    }
}
private struct JobRow: View {
    let job: TranscriptionJob

    var body: some View {
        HStack(spacing: NotedSpacing.sm) {
            Image(systemName: job.state.systemImage)
                .foregroundStyle(statusColor)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: job.state == .transcribing)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(job.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(job.state.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, NotedSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.title), \(job.state.title)")
    }

    private var statusColor: Color {
        switch job.state {
        case .queued: .secondary
        case .transcribing: .notedMemory
        case .ready: .notedSuccess
        case .failed: .notedAttention
        }
    }
}
